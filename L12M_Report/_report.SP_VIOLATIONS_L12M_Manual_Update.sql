USE [HP_MAP_Prod]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- 10/11/19 CH SZ request to have four sellers expanded for all subcategories
-- 11/1/19 GG Request to have HP Added; BP request for Adorama; all subcategories
-- 4/20/20 LU replaced Seller temp table with _ref table.
-- 5/29/20 CH Added PCs; replaced G20 Sel/Category Flag CASE WHEN with _ref table connection
-- 7/31/20 LU Added Automatic Threshold calculation rules
-- 9/10/20 LU adjusted to include relevant days even if no data loaded. Adjusted to add contact information.
-- 9/28/20 LU Adjusted to remove non PC ACB violations
-- 9/29/20 LU Adjusted to remove violations matching Frys violations on >= Price/SKU/Week. -- 10/16/20 also excluding Zoro (WW Grainger)
-- 10/30/20 LU Adjusted to add Seller Name
-- 1/25/21 LU - temporarily adjusted due to Notebook violations showing up as Product Type Reporting "Default" in ViolationsMAP
-- 1/29/21 LU replaced _temp.Daily_MAP_Violations_VI with _analysis table. BG Team given access to _analysis.
-- 2/19/21 LU Removed Zoro Matching. Keeping Frys per HP Feedback.
-- 7/16/21 CH added Violation Code Ranking to ViolationsMAP to get over duplicate FactIDs due to stacking ViolationsCPL (QC) on top of ViolationsMAP
-- 10/11/22 CH adding PS SKUs/Categories
-- 1/19/23 DP C-SKU Integration + Status/Contacts updates for C-SKUs
-- 2/14/23 ED Added Buffer Periods
-- 4/12/23 RV Join tables on SID instead of Account for ##output tables
-- 04/28/23 ED: Adding 'Validation Status New' to diferentiate between accepted violations contr. to threshold vs not contr. to threshold
-- 05/01/23 RV: Indexes on temp tables
-- 05/29/23 ED: G-SKU integration
-- 07/11/23 ED: Removing Violation Code 7
-- 07/30/23 ED: HPS/OPS integration
-- 09/12/23 ED: Limiting Corsearch data to Unauthorized only
-- 10/26/23 ED: Inkjet/LaserJet integration
-- 11/1/23 ED: Removing join to _analysis.SKUList_MT_Master table, replacing with In MAP Scope condition for Dim Product
-- 03/02/24 ED: Removing Quantity=1 condition due to Bundles launch
-- 03/18/24 ED: Adding Live Link where Screenshot_URL is N/A
-- 06/14/24 ED: Opening scope of Internal contacts from G35 only to all
-- 07/04/24 ED: Adding Minimum Violation Date & Minimum Listing Date per HP request (since 11/01/23, PM data only)
-- 09/11/24 ED: Adding Date Requested for PM scraping sites due to HP request
-- 09/13/24 ED: Adding New SKU table and flag
-- 09/19/24 ZF: Updating date range to start at beginning of week and cover 13 full months
-- 10/09/24 ED: Adding Seller Ranking based on number of raw violations (regardless of VI status); Switched from global to temp tables for the outputs
-- 10/09/24 ED: Adding Most Recent Listing Date
-- 10/14/24 ED: Adding condition LID <> N/A for the prep outputs to speed up execution
-- 10/23/24 ED: Moving C-SKU/G-SKU under Supplies
-- 10/23/24 ED: Adding MAX Courtesy Alert Date
-- 11/01/24 ED: Adding Grace Period SKU Flag
-- 12/04/24 ED: Adding HP Rep Names
-- 05/13/25 ED: Adding Content Provider
-- 05/21/25 ED: Adding Closed Websites listings for the same Seller/SKU/Day as Open Websites
-- 06/17/25 ED: Adding Strikethrough Flag
-- 09/04/26 PB Updated for the MAP New Framework and isolated Analysis testing.
-- 09/04/26 PB Daily VI, legacy Fact-derived violation, legacy source, Courtesy Alert, G20, forecast FIN, running-total and seller-rank logic retired.
-- 09/04/26 PB Added historical Warning monitoring and Consequence penalty periods plus Flag_Warning_Or_Monitoring.
-- 09/17/26 PB Restored top-seller membership and weekly seller ranking without restoring projected FIN or RunningTotal.
ALTER PROCEDURE [_report].[SP_VIOLATIONS_L12M]
@P_Export_Start_Date DATE = NULL,
@P_Generate_Full_Refresh BIT = 0,
@P_Through_Date DATE = NULL
AS
BEGIN
SET TRANSACTION ISOLATION LEVEL READ COMMITTED
SET NOCOUNT ON
SET XACT_ABORT ON

IF @@TRANCOUNT <> 0
BEGIN
	;THROW 51000, 'Run the L12M report outside a transaction.', 1
END

DECLARE @BusinessToday DATE = CONVERT(DATE, SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'Eastern Standard Time')
DECLARE @ThroughDate DATE = COALESCE(@P_Through_Date, DATEADD(DAY, -1, @BusinessToday))
DECLARE @StartDate DATE =
(
	SELECT d.Week_Begin_Date_Alt
	FROM HP_MAP_Prod._final.Dim_Date AS d
	WHERE d.Full_Date = DATETRUNC(MONTH, DATEADD(MONTH, -12, @BusinessToday))
)
DECLARE @ExportStartDate DATE =
	CASE
		WHEN @P_Export_Start_Date IS NOT NULL THEN @P_Export_Start_Date
		WHEN @P_Generate_Full_Refresh = 1 THEN @StartDate
		ELSE
		(
			SELECT d.Week_Begin_Date_Alt
			FROM HP_MAP_Prod._final.Dim_Date AS d
			WHERE d.Full_Date = DATETRUNC(WEEK, DATEADD(WEEK, -2, @BusinessToday))
		)
	END

IF @StartDate IS NULL OR @ExportStartDate IS NULL
	OR @ExportStartDate < @StartDate OR @ExportStartDate > @ThroughDate OR @ThroughDate >= @BusinessToday
BEGIN
	;THROW 51000, 'Invalid L12M calendar, export start or through date.', 1
END

DROP TABLE IF EXISTS #Product_Category
CREATE TABLE #Product_Category
(
	[Product Category] NVARCHAR(255) NOT NULL,
	[Product Subcategory] NVARCHAR(50) NOT NULL,
	[Product Subcategory Enforcement] NVARCHAR(255) NOT NULL,
	[Rule Product Type] NVARCHAR(50) NOT NULL
)

INSERT INTO #Product_Category
(
	[Product Category],
	[Product Subcategory],
	[Product Subcategory Enforcement],
	[Rule Product Type]
)
VALUES
	('Supplies', 'Ink', 'Ink & Toner', 'Ink'),
	('Supplies', 'Toner', 'Ink & Toner', 'Toner'),
	('Supplies', 'C-SKU', 'Ink & Toner', 'Toner'),
	('Supplies', 'G-SKU', 'Ink & Toner', 'Toner'),
	('Print', 'Inkjet', 'Inkjet', 'Inkjet'),
	('Print', 'LaserJet', 'LaserJet', 'LaserJet'),
	('Large Format', 'Large Format', 'Large Format', 'Large Format'),
	('Large Format', 'Large Format Supplies', 'Large Format', 'Large Format Supplies'),
	('PS', 'BPS Display', 'BPS Display', 'BPS Display'),
	('PS', 'CPS Desktop', 'CPS Desktop', 'CPS Desktop'),
	('PS', 'CPS Display', 'CPS Display', 'CPS Display'),
	('PS', 'CPS Notebook', 'CPS Notebook', 'CPS Notebook')

DROP TABLE IF EXISTS #Weeks
SELECT DISTINCT
	dt.Week_Begin_Date_Alt AS [Week],
	dt.Full_Date AS [Date]
INTO #Weeks
FROM HP_MAP_Prod._final.Dim_Date AS dt  -- 9/10/20 LU adjusted to Dim_Date to include days even if no data loaded.
WHERE dt.Week_Begin_Date_Alt >= @StartDate
  AND dt.Full_Date < DATEADD(DAY, 1, @ThroughDate)

CREATE UNIQUE CLUSTERED INDEX IX_Weeks_Date ON #Weeks ([Date])

DROP TABLE IF EXISTS #UPC_US
DECLARE @MaxFileDateUPC_US DATE =
(
	SELECT MAX([File Date])
	FROM HP_MAP_Prod._analysis.MAP_Price_List_Tool_Export_NEW
)

SELECT
	SKU,
	MAX(ISNULL(UPC, '')) AS UPC
INTO #UPC_US
FROM HP_MAP_Prod._analysis.MAP_Price_List_Tool_Export_NEW
WHERE [File Date] = @MaxFileDateUPC_US
GROUP BY SKU

CREATE UNIQUE CLUSTERED INDEX IX_UPC_US_SKU ON #UPC_US (SKU)

DROP TABLE IF EXISTS #MinViolationDate
SELECT
	New_Location_ID,
	MIN(Collected_Date) AS [Minimum Violation Date]
INTO #MinViolationDate
FROM [_final].[ViolationsMAP]
WHERE Collected_Date >= '2023-11-01'
GROUP BY New_Location_ID

CREATE UNIQUE CLUSTERED INDEX IX_MinViolationDate_Location
	ON #MinViolationDate (New_Location_ID)

-- Use listings for the first and last listing dates.
DROP TABLE IF EXISTS #Min_Max_Listing_Date
SELECT
	s.Master_New_Location_Id,
	MIN(CAST(f.Collected_Date AS DATE)) AS [Minimum Listing Date],
	MAX(CAST(f.Collected_Date AS DATE)) AS [Most Recent Listing Date]
INTO #Min_Max_Listing_Date
FROM HP_MAP_Prod._final.Fact_Listings AS f
INNER JOIN HP_MAP_Prod._final.Dim_Seller AS s
	ON s.Seller_ID = f.Seller_ID
WHERE CAST(f.Collected_Date AS DATE) >= '2023-11-01'
  AND s.Master_New_Location_Id <> 'N/A'
GROUP BY s.Master_New_Location_Id

CREATE UNIQUE CLUSTERED INDEX IX_MinMaxListingDate_Location
	ON #Min_Max_Listing_Date (Master_New_Location_Id)

DROP TABLE IF EXISTS #DateRequested
SELECT
	Country AS Ctry,
	Master_New_Location_Id,
	MIN(Date_Requested) AS [Date Requested]
INTO #DateRequested
FROM HP_MAP_Prod._analysis.PM_Monitoring_List
GROUP BY Country, Master_New_Location_Id

CREATE NONCLUSTERED INDEX IX_DateRequested_Country_Location
	ON #DateRequested (Ctry, Master_New_Location_Id)

DROP TABLE IF EXISTS #NewSKU
SELECT DISTINCT SKU
INTO #NewSKU
FROM HP_MAP_Prod._ref.SKU_Enforcement_Exclusion
WHERE Flag_Reporting = 1

CREATE UNIQUE CLUSTERED INDEX IX_NewSKU_SKU ON #NewSKU (SKU)

DROP TABLE IF EXISTS #Grace_Period
SELECT DISTINCT
	CAST('US' AS NVARCHAR(10)) AS Country,
	SKU,
	Valid_From,
	Valid_To
INTO #Grace_Period
FROM HP_MAP_Prod._ref.Grace_Period_SKUs

CREATE NONCLUSTERED INDEX IX_GracePeriod_SKU_Dates
	ON #Grace_Period (SKU, Valid_From, Valid_To)

DROP TABLE IF EXISTS #Content
;WITH RankedContent AS
(
	SELECT
		CAST('US' AS NVARCHAR(10)) AS Country,
		b.HPI_Location_ID,
		b.Content_Provider AS Content_Source,
		ROW_NUMBER() OVER
		(
			PARTITION BY b.HPI_Location_ID
			ORDER BY b.Create_Date DESC
		) AS RN
	FROM HP_QPP_Prod._WEB.tbl_assessment_form_bg AS b
	WHERE b.Flag_Active = 1
	  AND b.Flag_Current = 1
	  AND b.Country IN ('US', 'USA')
)
SELECT
	Country,
	HPI_Location_ID,
	Content_Source
INTO #Content
FROM RankedContent
WHERE RN = 1

CREATE UNIQUE CLUSTERED INDEX IX_Content_Country_Location
	ON #Content (Country, HPI_Location_ID)

-- Read active US partners once for both lookups.
DROP TABLE IF EXISTS #ActiveQPP
SELECT
	CONVERT(NVARCHAR(20), p.HPI_Location_ID) AS HPI_Location_ID,
	MAX(p.[Status]) AS Partner_Status,
	MAX(p.Drop_Date) AS Drop_Date,
	MAX(p.Action_Required) AS Action_Required,
	MAX(p.Expiration_Date) AS Expiration_Date
INTO #ActiveQPP
FROM HP_QPP_Prod._web.tbl_Partner AS p
WHERE p.Flag_Active = 1
  AND p.Flag_Current = 1
  AND p.[Status] = 'Active'
  AND p.Country IN ('US', 'USA')
GROUP BY CONVERT(NVARCHAR(20), p.HPI_Location_ID)

CREATE UNIQUE CLUSTERED INDEX IX_ActiveQPP_Location
	ON #ActiveQPP (HPI_Location_ID)

DROP TABLE IF EXISTS #PartnerLookup
SELECT
	CONVERT(NVARCHAR(20), p.LocationId) AS LocationId,
	MAX(p.Id) AS Partner_ID
INTO #PartnerLookup
FROM HP_QPP_Prod.dbo.N_Partners AS p
GROUP BY CONVERT(NVARCHAR(20), p.LocationId)

CREATE UNIQUE CLUSTERED INDEX IX_PartnerLookup_Location
	ON #PartnerLookup (LocationId)

DROP TABLE IF EXISTS #ValidNotifications
SELECT
	n.ID,
	n.Notification_ID,
	CONVERT(NVARCHAR(20), n.New_Location_ID) AS New_Location_ID,
	CONVERT(NVARCHAR(50), n.Product_Type) AS Product_Type,
	n.Letter_Type,
	n.Generation_Date,
	n.Communication_Sent_Date,
	n.Communication_Delivered_Date,
	n.DGF_Penalty
INTO #ValidNotifications
FROM [_ref].[Notifications_MAP] AS n
WHERE n.Notification_Approval_Status <> 0
  AND ISNULL(n.Wrong_Notification_Flag, 0) = 0
  AND ISNULL(n.Exception_Flag, 0) = 0

CREATE CLUSTERED INDEX IX_ValidNotifications_Location_Product_Generation
	ON #ValidNotifications
	(
		New_Location_ID,
		Product_Type,
		Generation_Date DESC,
		Notification_ID DESC,
		ID DESC
	)

CREATE NONCLUSTERED INDEX IX_ValidNotifications_Notification
	ON #ValidNotifications (Notification_ID, New_Location_ID, Product_Type)
	INCLUDE (Letter_Type, DGF_Penalty)

DROP TABLE IF EXISTS #StoreFrontNames
SELECT
	Country,
	New_Location_ID,
	STRING_AGG(CONVERT(NVARCHAR(MAX), Storefront_Names), '; ')
		WITHIN GROUP (ORDER BY MPA_Date ASC) AS StoreFrontName
INTO #StoreFrontNames
FROM
(
	SELECT DISTINCT
		CONVERT(NVARCHAR(10), Country) AS Country,
		CONVERT(NVARCHAR(20), New_Location_ID) AS New_Location_ID,
		Storefront_Names,
		MPA_Date
	FROM HP_MAP_Prod._ref.Marketplace_Approved
	WHERE Flag_Active = 1
	  AND Flag_Current = 1
	  AND Country = 'US'
) AS ApprovedStorefronts
GROUP BY Country, New_Location_ID

CREATE UNIQUE CLUSTERED INDEX IX_StoreFrontNames_Country_Location
	ON #StoreFrontNames (Country, New_Location_ID)

-- Fiscal Week Calculation
DROP TABLE IF EXISTS #Fiscal_Week
;WITH FiscalWeeks AS
(
	SELECT DISTINCT
		Fiscal_Year,
		Week_Begin_Date_Alt,
		DENSE_RANK() OVER
		(
			PARTITION BY Fiscal_Year
			ORDER BY Week_Begin_Date_Alt
		) AS Fiscal_Week_Number
	FROM HP_MAP_Prod._final.Dim_Date
)
SELECT DISTINCT
	Week_Begin_Date_Alt,
	Fiscal_Week_Number
INTO #Fiscal_Week
FROM FiscalWeeks
WHERE Fiscal_Week_Number < 53
  AND Week_Begin_Date_Alt >= '2015-11-01'

CREATE UNIQUE CLUSTERED INDEX IX_FiscalWeek_Week
	ON #Fiscal_Week (Week_Begin_Date_Alt)

-- Build the US violation rows.

DROP TABLE IF EXISTS #ViolationRows
-- Keep every matching product and seller row.
SELECT
	dp.[CSKU_Flag], dp.[Government_SKU_Flag], dp.[In_MAP_Scope_Flag], dp.[Product_Category_Reporting],
	dp.[Product_Description], dp.[Product_Type_Indirect_MAP], dp.[SKU], dp.[Valid_From], dp.[Valid_To]
INTO #MAP_L12M_US_Product
FROM HP_MAP_Prod._final.Dim_Product AS dp
WHERE dp.Valid_From < DATEADD(DAY, 1, @ThroughDate) AND dp.Valid_To >= @StartDate
  AND dp.In_MAP_Scope_Flag = 'In MAP Scope'
OPTION (MAXDOP 2, RECOMPILE)
CREATE INDEX IX_MAP_L12M_Product ON #MAP_L12M_US_Product (SKU, Valid_From, Valid_To)
SELECT
	sel.[Master_New_Location_Id], sel.[Print_Qualification], sel.[Qualified_Business_Personal_Systems],
	sel.[Qualified_Consumer_Personal_Systems], sel.[Supplies_Qualification], sel.[Valid_From],
	sel.[Valid_To]
INTO #MAP_L12M_US_Seller
FROM HP_MAP_Prod._final.Dim_Seller AS sel
WHERE sel.Valid_From < DATEADD(DAY, 1, @ThroughDate) AND sel.Valid_To >= @StartDate
OPTION (MAXDOP 2, RECOMPILE)
CREATE INDEX IX_MAP_L12M_Seller ON #MAP_L12M_US_Seller (Master_New_Location_Id, Valid_From, Valid_To)
SELECT TOP (0)
	v.[Collected_Date], v.[Comments], v.[Data_Source], v.[Eligible_IR_Amount], v.[Fact_ID],
	v.[Flag_Bundle], v.[HP_Reason_ID], v.[Listing_ID], v.[Login_Type_ID], v.[Lowest_Possible_Price],
	v.[MAP], v.[Market], v.[Market_Unified], v.[Master_SID], v.[New_Location_ID], v.[Notification_ID],
	v.[Price_Location], v.[Product_Page], v.[Product_Type_Enforcement], v.[Reason_ID], v.[Screenshot_URL],
	v.[Seller_Advertised_Price], v.[Seller_Name], v.[Seller_Name_Unified], v.[Seller_Penalty_Type],
	v.[Seller_Reporting_Group], v.[SKU], v.[Tier_Pass_Through], v.[Validation_Status], v.[Violation_Code],
	CONVERT(INT, v.Violation_ID) AS Violation_ID, v.[Week_Start_Date]
INTO #MAP_L12M_US_Batch
FROM [_final].[ViolationsMAP] AS v
CREATE INDEX IX_MAP_L12M_Batch_SKU ON #MAP_L12M_US_Batch (SKU, Collected_Date)
SELECT TOP (0) CONVERT(BIGINT, nm.ID) AS ID, nm.ASIN, nm.Listing_URL INTO #MAP_L12M_US_Listings FROM HP_MAP_Prod._final.Seller_Pricing_NewMo AS nm
CREATE UNIQUE CLUSTERED INDEX IX_MAP_L12M_Listings ON #MAP_L12M_US_Listings (ID)
DECLARE @MAP_L12M_US_BatchStart DATE = @StartDate, @MAP_L12M_US_BatchEnd DATE = DATEADD(DAY, 1, @StartDate)
SELECT IDENTITY(BIGINT, 1, 1) AS MAP_RowToken, base.* INTO #MAP_L12M_US_Base
FROM (
	SELECT
		v.Violation_ID,
		v.Fact_ID AS [Fact ID],
		v.Week_Start_Date AS [Week],
		v.Collected_Date AS [Date],
		dp.Product_Category_Reporting AS [Product Category],
		CASE
			WHEN dp.CSKU_Flag = 'C-SKU' THEN 'C-SKU'
			WHEN dp.Government_SKU_Flag = 'Government SKU'
			 AND dp.Product_Category_Reporting = 'Supplies' THEN 'G-SKU'
			ELSE dp.Product_Type_Indirect_MAP
		END AS [Product Subcategory],
		COALESCE
		(
			v.Product_Type_Enforcement,
			CASE
				WHEN dp.Product_Type_Indirect_MAP IN ('Ink', 'Toner') THEN 'Ink & Toner'
				WHEN dp.Product_Type_Indirect_MAP LIKE 'Large Format%' THEN 'Large Format'
				ELSE dp.Product_Type_Indirect_MAP
			END
		) AS [Product Subcategory Enforcement],
		v.SKU,
		UPPER(NULLIF(nm.ASIN, 'N/A')) AS ASIN,
		-- Use the product description from the same date as the category.
		dp.Product_Description AS Product_Description,
		v.Seller_Name_Unified AS Account,
		v.Seller_Name AS [Seller Name],
		v.New_Location_ID AS [Location ID],
		v.Master_SID,
		v.Seller_Penalty_Type AS [Seller Penalty Type],
		v.Seller_Reporting_Group AS [Reporting Group],
		v.Market_Unified AS Market,
		CASE WHEN ISNULL(v.Login_Type_ID, 1) = 3 THEN 'Free log-in' ELSE 'Public Site' END AS [Log-in Type],
		v.Price_Location AS [Price Location],
		v.MAP,
		v.Seller_Advertised_Price AS [Advertised Price],
		v.Eligible_IR_Amount AS [Eligible IR],
		v.Lowest_Possible_Price AS [Lowest Possible Price],
		COALESCE(NULLIF(v.Screenshot_URL, 'N/A'), v.Product_Page, nm.Listing_URL, 'N/A') AS Screenshot_URL,
		ISNULL(v.Validation_Status, 'Not Inspected') AS Validation_Status_Raw,
		COALESCE(hpres.Reason_Description, res.Reason_Description, v.Comments) AS Notes,
		v.Tier_Pass_Through,
		ISNULL(v.Flag_Bundle, 0) AS Flag_Bundle,
		ISNULL(v.Login_Type_ID, 1) AS Login_Type_ID,
		CASE WHEN v.Violation_Code = 8 THEN 1 ELSE 0 END AS Flag_StrikeThrough,
		CASE
			WHEN v.Violation_Code = 6 THEN 'C-SKU - Restricted'
			WHEN v.Violation_Code = 8 THEN 'Strike-through'
			WHEN v.Violation_Code = 9 THEN 'Price - Coupon'
			WHEN v.Flag_Bundle = 1 THEN 'Price - Bundle'
			WHEN v.Price_Location IN ('Product Page Ad', 'Product Page') THEN 'Price - Product Page'
			WHEN v.Price_Location = 'Shopping Cart' THEN 'Price - In-Cart'
			ELSE 'Electronic Content'
		END AS Violation_Type,
		CASE
			WHEN v.Market IN ('Websites US', 'Best Buy') --CH 9/24/19 Added Best Buy
			  OR (v.Market = 'Amazon' AND v.New_Location_ID = '10322374')
			  OR (v.Market = 'Newegg' AND v.New_Location_ID = '10319396')
			  OR (v.Market = 'Walmart' AND v.New_Location_ID = '10256711') THEN 1
			WHEN v.Market = 'Amazon' THEN 2
			WHEN v.Market = 'Walmart' THEN 3
			WHEN v.Market = 'eBay' THEN 4
			WHEN v.Market = 'Newegg' THEN 5
			ELSE 6
		END AS Market_ID,
		CASE
			WHEN qpp.HPI_Location_ID IS NOT NULL
				THEN HP_MAP_Prod.dbo.FN_GET_SELLER_STATUS
				(
					dp.Product_Category_Reporting,
					sel.Supplies_Qualification,
					sel.Print_Qualification,
					sel.Qualified_Business_Personal_Systems,
					sel.Qualified_Consumer_Personal_Systems
				)
			ELSE 'Unauthorized'
		END AS Seller_Status,
		CASE
			WHEN qpp.Partner_Status = 'Dropped' THEN qpp.Drop_Date
			WHEN qpp.Action_Required = 'PA Termination' THEN qpp.Expiration_Date
			ELSE NULL
		END AS [Termination Date],
		v.Notification_ID,
		linked_notification.DGF_Penalty,
		CASE
			WHEN v.Validation_Status = 'Accepted'
			 AND LEFT(linked_notification.Letter_Type, 1) = 'W' THEN 1
			ELSE 0
		END AS Flag_Triggered_Warning
	FROM #MAP_L12M_US_Batch AS v
	INNER JOIN #MAP_L12M_US_Product AS dp
		ON dp.SKU = v.SKU
	   AND v.Collected_Date BETWEEN dp.Valid_From AND dp.Valid_To
	   AND dp.In_MAP_Scope_Flag = 'In MAP Scope'
	INNER JOIN #MAP_L12M_US_Seller AS sel
		ON sel.Master_New_Location_Id = v.New_Location_ID
	   AND v.Collected_Date BETWEEN sel.Valid_From AND sel.Valid_To
	LEFT JOIN #MAP_L12M_US_Listings AS nm
		ON nm.ID = v.Listing_ID
	   AND v.Data_Source IN ('NewMo', 'Pervasive Mind')
	LEFT JOIN HP_MAP_Prod._ref.Rejection_Reasons AS res
		ON res.Reason_ID = v.Reason_ID
	LEFT JOIN HP_MAP_Prod._ref.HP_Rejection_Reasons AS hpres
		ON hpres.HP_Reason_ID = v.HP_Reason_ID
	LEFT JOIN #ActiveQPP AS qpp
		ON qpp.HPI_Location_ID = v.New_Location_ID
	OUTER APPLY
	(
		SELECT TOP (1)
			n.Letter_Type,
			n.DGF_Penalty
		FROM #ValidNotifications AS n
		WHERE n.Notification_ID = v.Notification_ID
		  AND n.New_Location_ID = v.New_Location_ID
		  AND n.Product_Type = v.Product_Type_Enforcement
		ORDER BY n.Generation_Date DESC, n.ID DESC
	) AS linked_notification
	WHERE v.Collected_Date >= @MAP_L12M_US_BatchStart
	  AND v.Collected_Date < @MAP_L12M_US_BatchEnd    -- 4/6/20 LU: due to intraday launch, need to restrict violations from current date
	  AND (qpp.HPI_Location_ID IS NOT NULL OR v.New_Location_ID = '99999999')
) AS base WHERE 1 = 0
CREATE UNIQUE CLUSTERED INDEX IX_MAP_L12M_Base_Token ON #MAP_L12M_US_Base (MAP_RowToken)
WHILE @MAP_L12M_US_BatchStart <= @ThroughDate
BEGIN
	TRUNCATE TABLE #MAP_L12M_US_Batch
	TRUNCATE TABLE #MAP_L12M_US_Listings
	INSERT INTO #MAP_L12M_US_Batch
	(
		[Collected_Date], [Comments], [Data_Source], [Eligible_IR_Amount], [Fact_ID], [Flag_Bundle],
		[HP_Reason_ID], [Listing_ID], [Login_Type_ID], [Lowest_Possible_Price], [MAP], [Market],
		[Market_Unified], [Master_SID], [New_Location_ID], [Notification_ID], [Price_Location], [Product_Page],
		[Product_Type_Enforcement], [Reason_ID], [Screenshot_URL], [Seller_Advertised_Price], [Seller_Name],
		[Seller_Name_Unified], [Seller_Penalty_Type], [Seller_Reporting_Group], [SKU], [Tier_Pass_Through],
		[Validation_Status], [Violation_Code], [Violation_ID], [Week_Start_Date]
	)
	SELECT
		v.[Collected_Date], v.[Comments], v.[Data_Source], v.[Eligible_IR_Amount], v.[Fact_ID],
		v.[Flag_Bundle], v.[HP_Reason_ID], v.[Listing_ID], v.[Login_Type_ID], v.[Lowest_Possible_Price],
		v.[MAP], v.[Market], v.[Market_Unified], v.[Master_SID], v.[New_Location_ID], v.[Notification_ID],
		v.[Price_Location], v.[Product_Page], v.[Product_Type_Enforcement], v.[Reason_ID], v.[Screenshot_URL],
		v.[Seller_Advertised_Price], v.[Seller_Name], v.[Seller_Name_Unified], v.[Seller_Penalty_Type],
		v.[Seller_Reporting_Group], v.[SKU], v.[Tier_Pass_Through], v.[Validation_Status], v.[Violation_Code],
		v.[Violation_ID], v.[Week_Start_Date]
	FROM [_final].[ViolationsMAP] AS v
	WHERE v.Collected_Date >= @MAP_L12M_US_BatchStart AND v.Collected_Date < @MAP_L12M_US_BatchEnd
	OPTION (MAXDOP 2, RECOMPILE)
	-- Look up each listing once per batch.
	INSERT INTO #MAP_L12M_US_Listings (ID, ASIN, Listing_URL)
	SELECT nm.ID, nm.ASIN, nm.Listing_URL
	FROM (SELECT DISTINCT Listing_ID FROM #MAP_L12M_US_Batch
		  WHERE Data_Source IN ('NewMo', 'Pervasive Mind') AND Listing_ID IS NOT NULL) AS keys_needed
	INNER LOOP JOIN HP_MAP_Prod._final.Seller_Pricing_NewMo AS nm WITH (INDEX([Idx_final_Seller_Pricing_NewMo_Id])) ON nm.ID = keys_needed.Listing_ID
	OPTION (MAXDOP 2, RECOMPILE)
	INSERT INTO #MAP_L12M_US_Base
	(
		[Violation_ID], [Fact ID], [Week], [Date], [Product Category], [Product Subcategory],
		[Product Subcategory Enforcement], [SKU], [ASIN], [Product_Description], [Account], [Seller Name],
		[Location ID], [Master_SID], [Seller Penalty Type], [Reporting Group], [Market], [Log-in Type],
		[Price Location], [MAP], [Advertised Price], [Eligible IR], [Lowest Possible Price], [Screenshot_URL],
		[Validation_Status_Raw], [Notes], [Tier_Pass_Through], [Flag_Bundle], [Login_Type_ID],
		[Flag_StrikeThrough], [Violation_Type], [Market_ID], [Seller_Status], [Termination Date],
		[Notification_ID], [DGF_Penalty], [Flag_Triggered_Warning]
	)
	SELECT
		v.Violation_ID,
		v.Fact_ID AS [Fact ID],
		v.Week_Start_Date AS [Week],
		v.Collected_Date AS [Date],
		dp.Product_Category_Reporting AS [Product Category],
		CASE
			WHEN dp.CSKU_Flag = 'C-SKU' THEN 'C-SKU'
			WHEN dp.Government_SKU_Flag = 'Government SKU'
			 AND dp.Product_Category_Reporting = 'Supplies' THEN 'G-SKU'
			ELSE dp.Product_Type_Indirect_MAP
		END AS [Product Subcategory],
		COALESCE
		(
			v.Product_Type_Enforcement,
			CASE
				WHEN dp.Product_Type_Indirect_MAP IN ('Ink', 'Toner') THEN 'Ink & Toner'
				WHEN dp.Product_Type_Indirect_MAP LIKE 'Large Format%' THEN 'Large Format'
				ELSE dp.Product_Type_Indirect_MAP
			END
		) AS [Product Subcategory Enforcement],
		v.SKU,
		UPPER(NULLIF(nm.ASIN, 'N/A')) AS ASIN,
		-- Use the product description from the same date as the category.
		dp.Product_Description AS Product_Description,
		v.Seller_Name_Unified AS Account,
		v.Seller_Name AS [Seller Name],
		v.New_Location_ID AS [Location ID],
		v.Master_SID,
		v.Seller_Penalty_Type AS [Seller Penalty Type],
		v.Seller_Reporting_Group AS [Reporting Group],
		v.Market_Unified AS Market,
		CASE WHEN ISNULL(v.Login_Type_ID, 1) = 3 THEN 'Free log-in' ELSE 'Public Site' END AS [Log-in Type],
		v.Price_Location AS [Price Location],
		v.MAP,
		v.Seller_Advertised_Price AS [Advertised Price],
		v.Eligible_IR_Amount AS [Eligible IR],
		v.Lowest_Possible_Price AS [Lowest Possible Price],
		COALESCE(NULLIF(v.Screenshot_URL, 'N/A'), v.Product_Page, nm.Listing_URL, 'N/A') AS Screenshot_URL,
		ISNULL(v.Validation_Status, 'Not Inspected') AS Validation_Status_Raw,
		COALESCE(hpres.Reason_Description, res.Reason_Description, v.Comments) AS Notes,
		v.Tier_Pass_Through,
		ISNULL(v.Flag_Bundle, 0) AS Flag_Bundle,
		ISNULL(v.Login_Type_ID, 1) AS Login_Type_ID,
		CASE WHEN v.Violation_Code = 8 THEN 1 ELSE 0 END AS Flag_StrikeThrough,
		CASE
			WHEN v.Violation_Code = 6 THEN 'C-SKU - Restricted'
			WHEN v.Violation_Code = 8 THEN 'Strike-through'
			WHEN v.Violation_Code = 9 THEN 'Price - Coupon'
			WHEN v.Flag_Bundle = 1 THEN 'Price - Bundle'
			WHEN v.Price_Location IN ('Product Page Ad', 'Product Page') THEN 'Price - Product Page'
			WHEN v.Price_Location = 'Shopping Cart' THEN 'Price - In-Cart'
			ELSE 'Electronic Content'
		END AS Violation_Type,
		CASE
			WHEN v.Market IN ('Websites US', 'Best Buy') --CH 9/24/19 Added Best Buy
			  OR (v.Market = 'Amazon' AND v.New_Location_ID = '10322374')
			  OR (v.Market = 'Newegg' AND v.New_Location_ID = '10319396')
			  OR (v.Market = 'Walmart' AND v.New_Location_ID = '10256711') THEN 1
			WHEN v.Market = 'Amazon' THEN 2
			WHEN v.Market = 'Walmart' THEN 3
			WHEN v.Market = 'eBay' THEN 4
			WHEN v.Market = 'Newegg' THEN 5
			ELSE 6
		END AS Market_ID,
		CASE
			WHEN qpp.HPI_Location_ID IS NOT NULL
				THEN HP_MAP_Prod.dbo.FN_GET_SELLER_STATUS
				(
					dp.Product_Category_Reporting,
					sel.Supplies_Qualification,
					sel.Print_Qualification,
					sel.Qualified_Business_Personal_Systems,
					sel.Qualified_Consumer_Personal_Systems
				)
			ELSE 'Unauthorized'
		END AS Seller_Status,
		CASE
			WHEN qpp.Partner_Status = 'Dropped' THEN qpp.Drop_Date
			WHEN qpp.Action_Required = 'PA Termination' THEN qpp.Expiration_Date
			ELSE NULL
		END AS [Termination Date],
		v.Notification_ID,
		linked_notification.DGF_Penalty,
		CASE
			WHEN v.Validation_Status = 'Accepted'
			 AND LEFT(linked_notification.Letter_Type, 1) = 'W' THEN 1
			ELSE 0
		END AS Flag_Triggered_Warning
	FROM #MAP_L12M_US_Batch AS v
	INNER JOIN #MAP_L12M_US_Product AS dp
		ON dp.SKU = v.SKU
	   AND v.Collected_Date BETWEEN dp.Valid_From AND dp.Valid_To
	   AND dp.In_MAP_Scope_Flag = 'In MAP Scope'
	INNER JOIN #MAP_L12M_US_Seller AS sel
		ON sel.Master_New_Location_Id = v.New_Location_ID
	   AND v.Collected_Date BETWEEN sel.Valid_From AND sel.Valid_To
	LEFT JOIN #MAP_L12M_US_Listings AS nm
		ON nm.ID = v.Listing_ID
	   AND v.Data_Source IN ('NewMo', 'Pervasive Mind')
	LEFT JOIN HP_MAP_Prod._ref.Rejection_Reasons AS res
		ON res.Reason_ID = v.Reason_ID
	LEFT JOIN HP_MAP_Prod._ref.HP_Rejection_Reasons AS hpres
		ON hpres.HP_Reason_ID = v.HP_Reason_ID
	LEFT JOIN #ActiveQPP AS qpp
		ON qpp.HPI_Location_ID = v.New_Location_ID
	OUTER APPLY
	(
		SELECT TOP (1)
			n.Letter_Type,
			n.DGF_Penalty
		FROM #ValidNotifications AS n
		WHERE n.Notification_ID = v.Notification_ID
		  AND n.New_Location_ID = v.New_Location_ID
		  AND n.Product_Type = v.Product_Type_Enforcement
		ORDER BY n.Generation_Date DESC, n.ID DESC
	) AS linked_notification
	WHERE v.Collected_Date >= @MAP_L12M_US_BatchStart
	  AND v.Collected_Date < @MAP_L12M_US_BatchEnd    -- 4/6/20 LU: due to intraday launch, need to restrict violations from current date
	  AND (qpp.HPI_Location_ID IS NOT NULL OR v.New_Location_ID = '99999999')
	OPTION (MAXDOP 2, RECOMPILE)
	SET @MAP_L12M_US_BatchStart = @MAP_L12M_US_BatchEnd
	SET @MAP_L12M_US_BatchEnd = DATEADD(DAY, 1, @MAP_L12M_US_BatchStart)
END
-- Calculate selectors before joining the wider report fields.
SELECT base.MAP_RowToken,
	MAX(CASE WHEN base.Validation_Status_Raw = 'Accepted' THEN 1 ELSE 0 END)
		OVER (PARTITION BY base.[Week], base.[Location ID], base.SKU, base.Login_Type_ID) AS Has_Accepted,
	MAX(CASE WHEN base.Validation_Status_Raw = 'Rejected' THEN 1 ELSE 0 END)
		OVER (PARTITION BY base.[Week], base.[Location ID], base.SKU, base.Login_Type_ID) AS Has_Rejected,
	ROW_NUMBER() OVER (PARTITION BY base.[Location ID], base.[Date], base.SKU, base.Login_Type_ID
		ORDER BY base.Flag_Triggered_Warning DESC,
			REPLACE(ISNULL(base.Validation_Status_Raw, 'Z'), 'Not Inspected', 'Z'),
			base.Market_ID, base.Violation_ID) AS Violation_ID_Selector
INTO #MAP_L12M_US_Signals FROM #MAP_L12M_US_Base AS base
OPTION (MAXDOP 2, RECOMPILE)
CREATE UNIQUE CLUSTERED INDEX IX_MAP_L12M_Signals ON #MAP_L12M_US_Signals (MAP_RowToken)
SELECT
	base.[Violation_ID], base.[Fact ID], base.[Week], base.[Date], base.[Product Category],
	base.[Product Subcategory], base.[Product Subcategory Enforcement], base.[SKU], base.[ASIN],
	base.[Product_Description], base.[Account], base.[Seller Name], base.[Location ID], base.[Master_SID],
	base.[Seller Penalty Type], base.[Reporting Group], base.[Market], base.[Log-in Type],
	base.[Price Location], base.[MAP], base.[Advertised Price], base.[Eligible IR],
	base.[Lowest Possible Price], base.[Screenshot_URL], base.[Validation_Status_Raw], base.[Notes],
	base.[Tier_Pass_Through], base.[Flag_Bundle], base.[Login_Type_ID], base.[Flag_StrikeThrough],
	base.[Violation_Type], base.[Market_ID], base.[Seller_Status], base.[Termination Date],
	base.[Notification_ID], base.[DGF_Penalty], base.[Flag_Triggered_Warning], signal.Has_Accepted,
	signal.Has_Rejected,
	CASE WHEN base.Validation_Status_Raw = 'Not Inspected' AND signal.Has_Accepted = 1 THEN 'Accepted - Derived'
		 WHEN base.Validation_Status_Raw = 'Not Inspected' AND signal.Has_Rejected = 1 THEN 'Rejected - Derived'
		 ELSE base.Validation_Status_Raw END AS [Validation Status],
	CASE WHEN signal.Has_Accepted = 1 THEN 'Accepted' WHEN signal.Has_Rejected = 1 THEN 'Rejected'
		 ELSE base.Validation_Status_Raw END AS [Validation Status Weekly],
	signal.Violation_ID_Selector
INTO #ViolationRows
FROM #MAP_L12M_US_Base AS base INNER JOIN #MAP_L12M_US_Signals AS signal ON signal.MAP_RowToken = base.MAP_RowToken
WHERE signal.Violation_ID_Selector = 1
OPTION (MAXDOP 2, RECOMPILE)
DROP TABLE #MAP_L12M_US_Signals, #MAP_L12M_US_Base, #MAP_L12M_US_Listings, #MAP_L12M_US_Batch, #MAP_L12M_US_Product, #MAP_L12M_US_Seller

CREATE NONCLUSTERED INDEX IX_ViolationRows_Location_Product_Date
	ON #ViolationRows ([Location ID], [Product Subcategory], [Date])
	INCLUDE (Master_SID, SKU, Login_Type_ID, Notification_ID)

DROP TABLE IF EXISTS #Sellers
;WITH RankedSellers AS
(
	SELECT
		v.Account,
		v.[Location ID],
		v.Master_SID,
		ROW_NUMBER() OVER
		(
			PARTITION BY v.[Location ID]
			ORDER BY v.[Date] DESC, v.Violation_ID DESC
		) AS RN
	FROM #ViolationRows AS v
)
SELECT
	Account,
	[Location ID],
	Master_SID
INTO #Sellers
FROM RankedSellers
WHERE RN = 1

CREATE UNIQUE CLUSTERED INDEX IX_Sellers_Location ON #Sellers ([Location ID])

DROP TABLE IF EXISTS #TopResellers
SELECT DISTINCT
	CONVERT(NVARCHAR(20), top_seller.Master_New_Location_Id) AS New_Location_ID
INTO #TopResellers
FROM HP_MAP_Prod._ref.Courtesy_Alerts_Top_Seller_List AS top_seller
INNER JOIN #Sellers AS seller
	ON seller.[Location ID] = top_seller.Master_New_Location_Id
WHERE top_seller.Master_New_Location_Id IS NOT NULL

CREATE UNIQUE CLUSTERED INDEX IX_TopResellers_Location
	ON #TopResellers (New_Location_ID)

DROP TABLE IF EXISTS #ValidStrikes
SELECT
	s.ID,
	s.Notification_ID,
	CONVERT(NVARCHAR(20), s.New_Location_ID) AS New_Location_ID,
	CONVERT(NVARCHAR(50), s.Product_Type) AS Product_Type,
	s.Violation_Status,
	s.Flag_Is_Active,
	s.Flag_Rehab,
	s.Flag_Cancelled,
	s.Buffer_Period_Start_Date,
	s.Buffer_Period_End_Date,
	s.Penalty_Period_Start_Date,
	s.Penalty_Period_End_Date_Adjusted,
	s.Product_Suspension_Start_Date,
	s.Product_Suspension_End_Date,
	s.Valid_From
INTO #ValidStrikes
FROM [dbo].[VI_MAP_Strikes_History] AS s
INNER JOIN #Sellers AS seller
	ON seller.[Location ID] = s.New_Location_ID
WHERE ISNULL(s.Flag_Cancelled, 0) = 0
  AND EXISTS
  (
	  SELECT 1
	  FROM #ValidNotifications AS n
	  WHERE n.Notification_ID = s.Notification_ID
		AND n.New_Location_ID = s.New_Location_ID
		AND n.Product_Type = s.Product_Type
  )
OPTION (RECOMPILE)

CREATE CLUSTERED INDEX IX_ValidStrikes_Location_Product_Period
	ON #ValidStrikes
	(
		New_Location_ID,
		Product_Type,
		Penalty_Period_Start_Date,
		Penalty_Period_End_Date_Adjusted
	)

CREATE NONCLUSTERED INDEX IX_ValidStrikes_Notification
	ON #ValidStrikes (Notification_ID, New_Location_ID, Product_Type)
	INCLUDE
	(
		ID,
		Violation_Status,
		Flag_Is_Active,
		Flag_Rehab,
		Buffer_Period_Start_Date,
		Buffer_Period_End_Date,
		Penalty_Period_Start_Date,
		Penalty_Period_End_Date_Adjusted,
		Product_Suspension_Start_Date,
		Product_Suspension_End_Date,
		Valid_From
	)

DROP TABLE IF EXISTS #LatestNotifications
;WITH RankedNotifications AS
(
	SELECT
		n.ID,
		n.Notification_ID,
		n.New_Location_ID,
		n.Product_Type,
		n.Letter_Type,
		n.Generation_Date,
		n.Communication_Sent_Date,
		n.Communication_Delivered_Date,
		n.DGF_Penalty,
		ROW_NUMBER() OVER
		(
			PARTITION BY n.New_Location_ID, n.Product_Type
			ORDER BY n.Generation_Date DESC, n.Notification_ID DESC, n.ID DESC
		) AS RN
	FROM #ValidNotifications AS n
	INNER JOIN #Sellers AS seller
		ON seller.[Location ID] = n.New_Location_ID
)
SELECT
	ID,
	Notification_ID,
	New_Location_ID,
	Product_Type,
	Letter_Type,
	Generation_Date,
	Communication_Sent_Date,
	Communication_Delivered_Date,
	DGF_Penalty
INTO #LatestNotifications
FROM RankedNotifications
WHERE RN = 1

CREATE UNIQUE CLUSTERED INDEX IX_LatestNotifications_Location_Product
	ON #LatestNotifications (New_Location_ID, Product_Type)

DROP TABLE IF EXISTS #LatestStrikes
;WITH RankedLatestStrikes AS
(
	SELECT
		s.*,
		ROW_NUMBER() OVER
		(
			PARTITION BY s.New_Location_ID, s.Product_Type
			ORDER BY s.Valid_From DESC, s.ID DESC
		) AS RN
	FROM #ValidStrikes AS s
	INNER JOIN #LatestNotifications AS n
		ON n.Notification_ID = s.Notification_ID
	   AND n.New_Location_ID = s.New_Location_ID
	   AND n.Product_Type = s.Product_Type
)
SELECT
	ID,
	Notification_ID,
	New_Location_ID,
	Product_Type,
	Flag_Is_Active,
	Flag_Rehab,
	Buffer_Period_Start_Date,
	Buffer_Period_End_Date,
	Penalty_Period_Start_Date,
	Penalty_Period_End_Date_Adjusted,
	Product_Suspension_Start_Date,
	Product_Suspension_End_Date
INTO #LatestStrikes
FROM RankedLatestStrikes
WHERE RN = 1

CREATE UNIQUE CLUSTERED INDEX IX_LatestStrikes_Location_Product
	ON #LatestStrikes (New_Location_ID, Product_Type)

-- Include the calendar, products and sellers needed by Tableau.
DROP TABLE IF EXISTS #CTE_cj
SELECT
	w.[Week],
	w.[Date],
	p.[Product Category],
	p.[Product Subcategory],
	p.[Product Subcategory Enforcement],
	p.[Rule Product Type],
	s.Account,
	ISNULL(LEFT(sf.StoreFrontName, 4000), 'Seller not Marketplace Approved') AS [Storefront Name(s)], -- 3/20 LU added for Storefront Name(s)
	s.[Location ID],
	s.Master_SID,
	ISNULL(rg.Penalty_Type, '30, 60, 90 Suspension') AS [Seller Penalty Type],
	ISNULL(rg.Reporting_Group, 'All') AS [Reporting Group]   -- 3/6 LU Added for MPA Reporting Group
INTO #CTE_cj
FROM #Weeks AS w
CROSS JOIN #Product_Category AS p
CROSS JOIN #Sellers AS s
LEFT JOIN #StoreFrontNames AS sf
	ON sf.New_Location_ID = s.[Location ID]
   AND sf.Country = 'US'
OUTER APPLY
(
	SELECT TOP (1)
		r.Penalty_Type,
		r.Reporting_Group
	FROM [_ref].[Seller_Reporting_Group] AS r
	WHERE r.Master_SID IN (s.Master_SID, -9999)
	  AND
	  (
		  r.Product_Type = p.[Rule Product Type]
		  OR r.Product_Type_Threshold = p.[Product Subcategory Enforcement]
	  )
	  AND w.[Date] BETWEEN r.Valid_From AND r.Valid_To
	ORDER BY
		CASE WHEN r.Master_SID = s.Master_SID THEN 0 ELSE 1 END,
		CASE WHEN r.Product_Type = p.[Rule Product Type] THEN 0 ELSE 1 END,
		r.Valid_From DESC,
		r.ID DESC
) AS rg

CREATE NONCLUSTERED INDEX IX_CTE_cj_Location_Product_Date
	ON #CTE_cj ([Location ID], [Product Subcategory], [Date])
	INCLUDE (Master_SID, [Week], [Product Subcategory Enforcement])

-- Get seller contacts for the report.
DROP TABLE IF EXISTS #SellerEmailInfo
SELECT DISTINCT
	CONVERT(NVARCHAR(20), i.New_Location_ID) AS New_Location_ID,
	CONVERT(NVARCHAR(100), i.Product_Type) AS Product_Type,
	CONVERT(NVARCHAR(100), i.Product_Category) AS Product_Category,
	LOWER(CONVERT(NVARCHAR(255), i.HP_Rep_1_Email)) AS Email1,
	LOWER(CONVERT(NVARCHAR(255), i.HP_Rep_2_Email)) AS Email2,
	LOWER(CONVERT(NVARCHAR(255), i.HP_Rep_3_Email)) AS Email3,
	LOWER(CONVERT(NVARCHAR(255), i.HP_Rep_4_Email)) AS Email4,
	LOWER(CONVERT(NVARCHAR(255), i.HP_Rep_5_Email)) AS Email5,
	LOWER(CONVERT(NVARCHAR(255), i.HP_Rep_6_Email)) AS Email6
INTO #SellerEmailInfo
FROM HP_MAP_Prod.dbo.VI_SELLERS_EMAIL_INFO_ALL AS i
INNER JOIN #Sellers AS seller
	ON seller.[Location ID] = i.New_Location_ID
WHERE i.Source_Rank = 1
OPTION (RECOMPILE)

CREATE NONCLUSTERED INDEX IX_SellerEmailInfo_Location
	ON #SellerEmailInfo (New_Location_ID)
	INCLUDE (Product_Type, Product_Category, Email1, Email2, Email3, Email4, Email5, Email6)

DROP TABLE IF EXISTS #SellerEmailUnion
SELECT
	LOWER(CONVERT(NVARCHAR(255), email_source.Email)) AS Email,
	MAX(CONVERT(NVARCHAR(255), email_source.Rep)) AS Rep
INTO #SellerEmailUnion
FROM HP_MAP_Prod._report.Seller_Email_Union AS email_source
WHERE email_source.Email IS NOT NULL
GROUP BY LOWER(CONVERT(NVARCHAR(255), email_source.Email))
OPTION (RECOMPILE)

CREATE UNIQUE CLUSTERED INDEX IX_SellerEmailUnion_Email
	ON #SellerEmailUnion (Email)

DROP TABLE IF EXISTS #ContactBase
;WITH ContactCandidates AS
(
	SELECT
		seller.Account AS [Seller Name Unified],
		seller.[Location ID] AS [New Location ID],
		product.[Product Category],
		i.Email1,
		i.Email2,
		i.Email3,
		i.Email4,
		i.Email5,
		i.Email6,
		ROW_NUMBER() OVER
		(
			PARTITION BY seller.[Location ID], product.[Product Category]
			ORDER BY
				i.Email1,
				i.Email2,
				i.Email3,
				i.Email4,
				i.Email5,
				i.Email6,
				i.Product_Type,
				i.Product_Category
		) AS RN
	FROM #Sellers AS seller
	CROSS JOIN
	(
		SELECT DISTINCT
			CASE
				WHEN [Product Subcategory] LIKE 'Large Format%' THEN 'Large Format'
				ELSE [Product Category]
			END AS [Product Category]
		FROM #Product_Category
	) AS product
	LEFT JOIN #SellerEmailInfo AS i
		ON i.New_Location_ID = seller.[Location ID]
	   AND
	   (
		   CASE WHEN i.Product_Type IN ('CPS', 'BPS') THEN i.Product_Type ELSE i.Product_Category END
		    = product.[Product Category]
		   OR (i.Product_Type = 'All' AND i.Product_Category = 'PC' AND product.[Product Category] IN ('CPS', 'BPS'))
	   )
)
SELECT
	[Seller Name Unified],
	[New Location ID],
	[Product Category],
	Email1,
	Email2,
	Email3,
	Email4,
	Email5,
	Email6
INTO #ContactBase
FROM ContactCandidates
WHERE RN = 1

DROP TABLE IF EXISTS #CTE_Contacts
SELECT
	contact.[Seller Name Unified],
	contact.[New Location ID],
	contact.[Product Category],
	MAX(CASE WHEN email_slot.Slot = 1 THEN rep.Rep END) AS HP_Rep1,
	MAX(CASE WHEN email_slot.Slot = 2 THEN rep.Rep END) AS HP_Rep2,
	MAX(CASE WHEN email_slot.Slot = 3 THEN rep.Rep END) AS HP_Rep3,
	MAX(CASE WHEN email_slot.Slot = 4 THEN rep.Rep END) AS HP_Rep4,
	MAX(CASE WHEN email_slot.Slot = 5 THEN rep.Rep END) AS HP_Rep5,
	MAX(CASE WHEN email_slot.Slot = 6 THEN rep.Rep END) AS HP_Rep6,
	MAX(CASE WHEN email_slot.Slot = 1 THEN email_slot.Email END) AS Email1,
	MAX(CASE WHEN email_slot.Slot = 2 THEN email_slot.Email END) AS Email2,
	MAX(CASE WHEN email_slot.Slot = 3 THEN email_slot.Email END) AS Email3,
	MAX(CASE WHEN email_slot.Slot = 4 THEN email_slot.Email END) AS Email4,
	MAX(CASE WHEN email_slot.Slot = 5 THEN email_slot.Email END) AS Email5,
	MAX(CASE WHEN email_slot.Slot = 6 THEN email_slot.Email END) AS Email6
INTO #CTE_Contacts
FROM #ContactBase AS contact
CROSS APPLY
(
	VALUES
		(1, contact.Email1),
		(2, contact.Email2),
		(3, contact.Email3),
		(4, contact.Email4),
		(5, contact.Email5),
		(6, contact.Email6)
) AS email_slot (Slot, Email)
LEFT JOIN #SellerEmailUnion AS rep
	ON rep.Email = email_slot.Email
GROUP BY
	contact.[Seller Name Unified],
	contact.[New Location ID],
	contact.[Product Category]

CREATE UNIQUE CLUSTERED INDEX IX_CTE_Contacts_Location_Category
	ON #CTE_Contacts ([New Location ID], [Product Category])

-- Build the US report rows.
DROP TABLE IF EXISTS #OutputBase
SELECT
	CAST('US' AS NVARCHAR(10)) AS Country,
	violation.[Validation Status],
	violation.[Validation Status Weekly],
	fiscal.Fiscal_Week_Number AS [Fiscal Week Number],
	scaffold.[Week],
	scaffold.[Date],
	scaffold.[Product Category],
	scaffold.[Product Subcategory],
	scaffold.[Product Subcategory Enforcement],
	CONVERT(BIGINT, violation.[Fact ID]) AS [Fact ID],
	violation.SKU,
	CONVERT(NVARCHAR(4000), violation.ASIN) AS ASIN,
	CONVERT(NVARCHAR(300), LEFT(violation.Product_Description, 300)) AS Product_Description,
	CONVERT
	(
		NVARCHAR(300),
		LEFT
		(
			CASE
				WHEN scaffold.[Location ID] = '10267108' THEN 'Office Products Center Inc'
				WHEN scaffold.Account = 'Target' THEN 'Target Corporatio'
				ELSE scaffold.Account
			END,
			300
		)
	) AS Account,
	CONVERT(NVARCHAR(300), LEFT(violation.[Seller Name], 300)) AS [Seller Name],
	CONVERT(NVARCHAR(4000), scaffold.[Storefront Name(s)]) AS [Storefront Name(s)], -- 3/20 LU Adding StoreFront Name(s)
	CONVERT(NVARCHAR(255), LEFT(scaffold.[Location ID], 255)) AS [Location ID],
	CONVERT
	(
		NVARCHAR(20),
		LEFT
		(
			CASE
				WHEN scaffold.[Location ID] = '99999999' THEN 'Qualified'
				WHEN qpp.HPI_Location_ID IS NOT NULL
					THEN HP_MAP_Prod.dbo.FN_GET_SELLER_STATUS
					(
						CASE
							-- Use the qualification category for the seller status lookup.
							WHEN scaffold.[Product Subcategory] = 'Large Format Supplies' THEN 'Supplies'
							WHEN scaffold.[Product Subcategory] = 'Large Format' THEN 'Print'
							WHEN scaffold.[Product Subcategory] = 'BPS Display' THEN 'BPS'
							WHEN scaffold.[Product Subcategory] IN ('CPS Desktop', 'CPS Display', 'CPS Notebook') THEN 'CPS'
							ELSE scaffold.[Product Category]
						END,
						seller_at_date.Supplies_Qualification,
						seller_at_date.Print_Qualification,
						seller_at_date.Qualified_Business_Personal_Systems,
						seller_at_date.Qualified_Consumer_Personal_Systems
					)
				ELSE 'Unauthorized'
			END,
			20
		)
	) AS [Seller Status],
	CONVERT
	(
		DATETIME,
		CASE
			WHEN qpp.Partner_Status = 'Dropped' THEN qpp.Drop_Date
			WHEN qpp.Action_Required = 'PA Termination' THEN qpp.Expiration_Date
			ELSE NULL
		END
	) AS [Termination Date],
	CONVERT(NVARCHAR(40), LEFT(COALESCE(violation.[Seller Penalty Type], scaffold.[Seller Penalty Type]), 40)) AS [Seller Penalty Type],
	CONVERT(NVARCHAR(40), LEFT(COALESCE(violation.[Reporting Group], scaffold.[Reporting Group], 'All'), 40)) AS [Reporting Group], -- 3/6 LU Added for MPA Reporting Group
	CONVERT(NVARCHAR(255), LEFT(violation.Market, 255)) AS Market,
	CONVERT(NVARCHAR(255), LEFT(violation.[Log-in Type], 255)) AS [Log-in Type],
	CONVERT(NVARCHAR(255), LEFT(violation.[Price Location], 255)) AS [Price Location],
	CONVERT(NUMERIC(19, 4), violation.MAP) AS MAP,
	CONVERT(NUMERIC(19, 4), violation.[Advertised Price]) AS [Advertised Price],
	CONVERT(NUMERIC(19, 4), violation.[Eligible IR]) AS [Eligible IR],
	CONVERT(NUMERIC(19, 4), violation.[Lowest Possible Price]) AS [Lowest Possible Price],
	CONVERT(NVARCHAR(255), LEFT(violation.Validation_Status_Raw, 255)) AS Validation_Status_Raw,
	CONVERT(NVARCHAR(255), LEFT(latest_notification.Letter_Type, 255)) AS [Letter Type],
	CONVERT
	(
		NVARCHAR(MAX),
		CASE
			WHEN latest_notification.Notification_ID IS NULL THEN 'N/A'
			WHEN latest_strike.Flag_Rehab = 1 OR (latest_strike.Flag_Is_Active = 0 AND NOT EXISTS
				 (SELECT 1 FROM HP_MAP_Prod._ref.MAP_Cutover_State AS retired
				  WHERE retired.Entity = 'STRIKE' AND retired.Source_Row_ID = latest_strike.ID
					AND retired.Cohort IN ('LEGACY_ONLY', 'EXCLUDE_EXPIRED_V2')))
				THEN CONCAT(latest_notification.Letter_Type, ' Rehabilitated')
			WHEN latest_notification.Communication_Sent_Date IS NULL
				THEN CONCAT(latest_notification.Letter_Type, ' To be Sent')
			WHEN latest_notification.Communication_Delivered_Date IS NULL
				THEN CONCAT(latest_notification.Letter_Type, ' Sent - Not Delivered')
			ELSE latest_notification.Letter_Type
		END
	) AS [MAP Status Detail],
	latest_notification.Communication_Delivered_Date AS [Letter Delivered Date],
	latest_notification.Generation_Date AS [Notification Generation Date],
	latest_strike.Buffer_Period_Start_Date AS [Buffer Period Start],
	latest_strike.Buffer_Period_End_Date AS [Buffer Period End],
	latest_strike.Product_Suspension_Start_Date AS [Product Suspension Start],
	latest_strike.Product_Suspension_End_Date AS [Product Suspension End],
	latest_strike.Penalty_Period_Start_Date AS [Penalty Period Start],
	latest_strike.Penalty_Period_End_Date_Adjusted AS [Penalty Period End],
	CONVERT(NVARCHAR(4000), LEFT(violation.Screenshot_URL, 4000)) AS Screenshot_URL,
	CONVERT(NUMERIC(38, 2), violation.DGF_Penalty) AS [DGF Penalty],
	CONVERT(NVARCHAR(200), LEFT(violation.Notes, 200)) AS Notes,
	CONVERT(NUMERIC(12, 2), violation.Tier_Pass_Through) AS Tier_Pass_Through,
	CONVERT
	(
		INT,
		CASE
			WHEN scaffold.[Location ID] = '99999999' THEN 1
			ELSE ISNULL(threshold_rule.Threshold_Action, threshold_fallback.Threshold_Action)
		END
	) AS [Category Threshold Highlight], -- Want to apply a threshold of 1 for HP
	CONVERT
	(
		INT,
		CASE
			WHEN scaffold.[Location ID] = '99999999' THEN 1
			ELSE ISNULL(threshold_rule.Threshold_Action, threshold_fallback.Threshold_Action)
		END
	) AS [Category Threshold Alert],
	contacts.HP_Rep1,
	contacts.HP_Rep2,
	contacts.HP_Rep3,
	contacts.HP_Rep4,
	contacts.HP_Rep5,
	contacts.HP_Rep6,
	contacts.Email1,
	contacts.Email2,
	contacts.Email3,
	contacts.Email4,
	contacts.Email5,
	contacts.Email6,
	CONVERT(INT, 0) AS [Matching Flag],
	CONVERT(INT, 0) AS [G20 Sel/Cat Flag],
	CAST(NULL AS NVARCHAR(255)) AS [Validation Status New],
	CAST(NULL AS INT) AS RunningTotal,
	ISNULL(upc.UPC, '') AS UPC,
	CONVERT(BIT, ISNULL(violation.Flag_Bundle, 0)) AS [Bundle Flag],
	min_violation.[Minimum Violation Date],
	listing_dates.[Minimum Listing Date],
	listing_dates.[Most Recent Listing Date],
	date_requested.[Date Requested],
	CONVERT(INT, CASE WHEN new_sku.SKU IS NOT NULL THEN 1 ELSE 0 END) AS [New SKU Flag],
	CONVERT(INT, CASE WHEN top_seller.New_Location_ID IS NULL THEN 0 ELSE 1 END) AS Top_Reseller_Flag,
	CAST(NULL AS DATE) AS [Latest Courtesy Alert Date],
	CONVERT(INT, ISNULL(violation.Login_Type_ID, 1)) AS Login_Type_ID,
	CONVERT
	(
		VARCHAR(25),
		CASE WHEN ISNULL(violation.Flag_StrikeThrough, 0) = 1
			 THEN 'Strikethrough Pricing' ELSE 'Non-Strikethrough Pricing' END
	) AS [Strikethrough Flag],
	CONVERT
	(
		INT,
		CASE
			WHEN ISNULL(violation.Flag_Bundle, 0) = 0
			 AND EXISTS
			 (
				 SELECT 1
				 FROM #Grace_Period AS gps
				 WHERE gps.Country = 'US'
				   AND gps.SKU = violation.SKU
				   AND scaffold.[Date] BETWEEN gps.Valid_From AND gps.Valid_To
			 ) THEN 1
			WHEN ISNULL(violation.Flag_Bundle, 0) = 1
			 AND EXISTS
			 (
				 SELECT 1
				 FROM #Grace_Period AS gps_bundle
				 WHERE gps_bundle.Country = 'US'
				   AND violation.SKU LIKE '%' + gps_bundle.SKU + '%'
				   AND scaffold.[Date] BETWEEN gps_bundle.Valid_From AND gps_bundle.Valid_To
			 ) THEN 1
			ELSE 0
		END
	) AS [Price Increase SKU Flag],
	CONVERT(NVARCHAR(255), LEFT(content.Content_Source, 255)) AS [Content Provider],
	partner.Partner_ID,
	CONVERT(NVARCHAR(20), LEFT(ISNULL(violation.Violation_Type, 'N/A'), 20)) AS [Violation Type],
	CAST(NULL AS DATE) AS [Product Category Latest Courtesy Alert Date],
	warning_period.Penalty_Period_Start_Date AS [Monitoring Period Start],
	warning_period.Penalty_Period_End_Date_Adjusted AS [Monitoring Period End],
	consequence_period.Penalty_Period_Start_Date AS [Consequence Penalty Period Start],
	consequence_period.Penalty_Period_End_Date_Adjusted AS [Consequence Penalty Period End],
	CONVERT
	(
		INT,
		CASE
			WHEN violation.Flag_Triggered_Warning = 1 THEN 2
			WHEN warning_period.ID IS NOT NULL THEN 1
			ELSE 0
		END
	) AS Flag_Warning_Or_Monitoring
INTO #OutputBase
FROM #CTE_cj AS scaffold
LEFT JOIN #ViolationRows AS violation
	ON violation.[Location ID] = scaffold.[Location ID]
   AND violation.Master_SID = scaffold.Master_SID --rv 4/12/23
   AND violation.[Product Subcategory] = scaffold.[Product Subcategory]
   AND violation.[Date] = scaffold.[Date]
LEFT JOIN #Fiscal_Week AS fiscal
	ON fiscal.Week_Begin_Date_Alt = scaffold.[Week]
LEFT JOIN #TopResellers AS top_seller
	ON top_seller.New_Location_ID = scaffold.[Location ID]
OUTER APPLY
(
	SELECT TOP (1)
		ds.Supplies_Qualification,
		ds.Print_Qualification,
		ds.Qualified_Business_Personal_Systems,
		ds.Qualified_Consumer_Personal_Systems
	FROM HP_MAP_Prod._final.Dim_Seller AS ds
	WHERE ds.Master_SID = scaffold.Master_SID
	  AND scaffold.[Date] BETWEEN ds.Valid_From AND ds.Valid_To
	ORDER BY ds.Valid_From DESC, ds.Seller_ID DESC
) AS seller_at_date
LEFT JOIN #ActiveQPP AS qpp
	ON qpp.HPI_Location_ID = scaffold.[Location ID]
LEFT JOIN #LatestNotifications AS latest_notification
	ON latest_notification.New_Location_ID = scaffold.[Location ID]
   AND latest_notification.Product_Type = scaffold.[Product Subcategory Enforcement]
LEFT JOIN #LatestStrikes AS latest_strike
	ON latest_strike.New_Location_ID = scaffold.[Location ID]
   AND latest_strike.Product_Type = scaffold.[Product Subcategory Enforcement]
-- Include past strikes when checking monitoring periods.
OUTER APPLY
(
	SELECT TOP (1)
		s.ID,
		s.Violation_Status,
		s.Penalty_Period_Start_Date,
		s.Penalty_Period_End_Date_Adjusted
	FROM #ValidStrikes AS s
	WHERE s.New_Location_ID = scaffold.[Location ID]
	  AND s.Product_Type = scaffold.[Product Subcategory Enforcement]
	  AND LEFT(s.Violation_Status, 1) = 'W'
	  AND scaffold.[Date] BETWEEN s.Penalty_Period_Start_Date
							  AND s.Penalty_Period_End_Date_Adjusted
	ORDER BY s.Penalty_Period_Start_Date DESC, s.ID DESC
) AS warning_period
OUTER APPLY
(
	SELECT TOP (1)
		s.ID,
		s.Violation_Status,
		s.Penalty_Period_Start_Date,
		s.Penalty_Period_End_Date_Adjusted
	FROM #ValidStrikes AS s
	WHERE s.New_Location_ID = scaffold.[Location ID]
	  AND s.Product_Type = scaffold.[Product Subcategory Enforcement]
	  AND LEFT(s.Violation_Status, 1) = 'C'
	  AND scaffold.[Date] BETWEEN s.Penalty_Period_Start_Date
							  AND s.Penalty_Period_End_Date_Adjusted
	ORDER BY s.Penalty_Period_Start_Date DESC, s.ID DESC
) AS consequence_period
OUTER APPLY
(
	SELECT
		CASE
			WHEN warning_period.ID IS NOT NULL THEN
				CASE warning_period.Violation_Status
					WHEN 'WF' THEN 'CF'
					WHEN 'W30' THEN 'C30'
					WHEN 'W60' THEN 'C60'
					WHEN 'W90' THEN 'C90'
					ELSE 'C30'
				END
			WHEN COALESCE(violation.[Seller Penalty Type], scaffold.[Seller Penalty Type]) LIKE '%Financial'
				THEN 'WF'
			WHEN consequence_period.Violation_Status = 'C30' THEN 'W60'
			WHEN consequence_period.Violation_Status IN ('C60', 'C90') THEN 'W90'
			ELSE 'W30'
		END AS Rule_Action
) AS threshold_action
OUTER APPLY
(
	SELECT TOP (1)
		r.Threshold_Action
	FROM [_ref].[Violation_Rules] AS r
	WHERE r.Program = 'MAP'
	  AND r.Seller_Group IN
		  (COALESCE(violation.[Reporting Group], scaffold.[Reporting Group], 'All'), 'All')
	  AND r.Penalty_Description = COALESCE(violation.[Seller Penalty Type], scaffold.[Seller Penalty Type])
	  AND r.Product_Type_Hybrid = scaffold.[Rule Product Type]
	  AND r.[Action] = threshold_action.Rule_Action
	  AND scaffold.[Date] BETWEEN r.Valid_From AND r.Valid_To
	ORDER BY
		CASE WHEN r.Seller_Group = COALESCE(violation.[Reporting Group], scaffold.[Reporting Group], 'All') THEN 0 ELSE 1 END,
		r.Valid_From DESC,
		r.ID DESC
) AS threshold_rule
OUTER APPLY
(
	SELECT
		CASE
			WHEN warning_period.ID IS NULL THEN 1
			WHEN scaffold.[Product Subcategory] IN ('Ink', 'Toner', 'C-SKU', 'G-SKU', 'Large Format Supplies') THEN 5
			ELSE 2
		END AS Threshold_Action
) AS threshold_fallback
LEFT JOIN #CTE_Contacts AS contacts
	ON contacts.[New Location ID] = scaffold.[Location ID]  -- 9/10/20 LU added for G20 Contacts
   AND contacts.[Product Category] =
	   CASE
		   WHEN scaffold.[Product Subcategory] LIKE 'Large Format%' THEN 'Large Format'
		   WHEN scaffold.[Product Subcategory] IN ('C-SKU', 'G-SKU') THEN 'Supplies' --DP 1/12/23 adjusting join so Supplies contacts apply to C-SKU in tooltip
		   ELSE scaffold.[Product Category]
	   END
LEFT JOIN #UPC_US AS upc
	ON upc.SKU = violation.SKU
LEFT JOIN #MinViolationDate AS min_violation
	ON min_violation.New_Location_ID = scaffold.[Location ID]
LEFT JOIN #Min_Max_Listing_Date AS listing_dates
	ON listing_dates.Master_New_Location_Id = scaffold.[Location ID]
LEFT JOIN #DateRequested AS date_requested
	ON date_requested.Master_New_Location_Id = scaffold.[Location ID]
   AND date_requested.Ctry = 'US'
LEFT JOIN #NewSKU AS new_sku
	ON new_sku.SKU = violation.SKU
LEFT JOIN #Content AS content
	ON content.HPI_Location_ID = scaffold.[Location ID]
   AND content.Country IN ('US', 'USA')
LEFT JOIN #PartnerLookup AS partner
	ON partner.LocationId = scaffold.[Location ID]
WHERE scaffold.[Location ID] <> 'N/A' -- 10/14/24 ED

CREATE NONCLUSTERED INDEX IX_OutputBase_Selector
	ON #OutputBase ([Location ID], [Date], SKU, Login_Type_ID)
	INCLUDE ([Week], [Product Subcategory], [Letter Type])

-- Rank the sellers in the report.
DROP TABLE IF EXISTS #WeeklySellerRanks
;WITH SellerWeeks AS
(
	SELECT
		output_base.Country,
		output_base.[Week],
		CONVERT(NVARCHAR(50), output_base.[Product Subcategory Enforcement]) AS [Product Subcategory Enforcement],
		output_base.Account,
		CONVERT(NVARCHAR(20), output_base.[Location ID]) AS [Location ID],
		MAX(output_base.Top_Reseller_Flag) AS Top_Reseller_Flag,
		COUNT(DISTINCT output_base.SKU) AS Violating_SKU_Count
	FROM #OutputBase AS output_base
	GROUP BY
		output_base.Country,
		output_base.[Week],
		CONVERT(NVARCHAR(50), output_base.[Product Subcategory Enforcement]),
		output_base.Account,
		CONVERT(NVARCHAR(20), output_base.[Location ID])
)
SELECT
	Country,
	[Week],
	[Product Subcategory Enforcement],
	[Location ID],
	DENSE_RANK() OVER
	(
		PARTITION BY Country, [Week], [Product Subcategory Enforcement]
		ORDER BY Top_Reseller_Flag DESC, Violating_SKU_Count DESC, Account
	) AS Weekly_Seller_Rank
INTO #WeeklySellerRanks
FROM SellerWeeks

CREATE UNIQUE CLUSTERED INDEX IX_WeeklySellerRanks_Week_Product_Location
	ON #WeeklySellerRanks
	(Country, [Week], [Product Subcategory Enforcement], [Location ID])

DROP TABLE IF EXISTS #FinalOutput
SELECT
	output_base.*,
	seller_rank.Weekly_Seller_Rank,
	ROW_NUMBER() OVER
	(
		PARTITION BY
			output_base.[Location ID],
			output_base.[Date],
			ISNULL(output_base.SKU, output_base.[Product Subcategory]),
			output_base.Login_Type_ID
		ORDER BY output_base.[Letter Type] DESC
	) AS Selector,
	ROW_NUMBER() OVER
	(
		PARTITION BY
			output_base.[Location ID],
			output_base.[Week],
			ISNULL(output_base.SKU, output_base.[Product Subcategory]),
			output_base.Login_Type_ID
		ORDER BY
			REPLACE(ISNULL(output_base.[Validation Status], 'Z'), 'Not Inspected', 'Z'),
			output_base.[Date]
	) AS [Weekly Violation Selector] -- 9/17/2020 LU: Moved up a line, certain weeks were't getting a WVS of 1
INTO #FinalOutput
FROM #OutputBase AS output_base
INNER JOIN #WeeklySellerRanks AS seller_rank
	ON seller_rank.Country = output_base.Country
   AND seller_rank.[Week] = output_base.[Week]
   AND seller_rank.[Product Subcategory Enforcement] = output_base.[Product Subcategory Enforcement]
   AND seller_rank.[Location ID] = output_base.[Location ID]

-- Build the Canada report using the shared US calendar.
DROP TABLE IF EXISTS #CA_Product_Category
CREATE TABLE #CA_Product_Category
(
	[Product Category] NVARCHAR(255) NOT NULL,
	[Product Subcategory] NVARCHAR(50) NOT NULL,
	[Product Subcategory Enforcement] NVARCHAR(255) NOT NULL,
	[Rule Product Type] NVARCHAR(50) NOT NULL
)

INSERT INTO #CA_Product_Category
(
	[Product Category],
	[Product Subcategory],
	[Product Subcategory Enforcement],
	[Rule Product Type]
)
VALUES
	('Supplies', 'Ink', 'Ink & Toner', 'Ink'),
	('Supplies', 'Toner', 'Ink & Toner', 'Toner'),
	('Supplies', 'C-SKU', 'Ink & Toner', 'Toner'),
	('Supplies', 'G-SKU', 'Ink & Toner', 'Toner'),
	('Print', 'Inkjet', 'Inkjet', 'Inkjet'),
	('Print', 'LaserJet', 'LaserJet', 'LaserJet'),
	('Large Format', 'Large Format', 'Large Format', 'Large Format'),
	('Large Format', 'Large Format Supplies', 'Large Format', 'Large Format Supplies'),
	('BPS', 'BPS Display', 'BPS Display', 'BPS Display'),
	('CPS', 'CPS Desktop', 'CPS Desktop', 'CPS Desktop'),
	('CPS', 'CPS Display', 'CPS Display', 'CPS Display'),
	('CPS', 'CPS Notebook', 'CPS Notebook', 'CPS Notebook')

UPDATE category_row
SET [Product Category] = native_category.Product_Category_Reporting
FROM #CA_Product_Category AS category_row
OUTER APPLY
(
	SELECT TOP (1) product_row.Product_Category_Reporting
	FROM HP_MAP_Canada._final.Dim_Product AS product_row
	WHERE product_row.Product_Type_Indirect_MAP = category_row.[Rule Product Type]
	  AND product_row.Product_Category_Reporting IS NOT NULL
	ORDER BY product_row.Flag_Current DESC, product_row.Valid_From DESC, product_row.Product_ID DESC
) AS native_category
WHERE category_row.[Product Subcategory] IN ('Large Format', 'Large Format Supplies')
  AND native_category.Product_Category_Reporting IS NOT NULL

DROP TABLE IF EXISTS #CA_UPC_US
DECLARE @MaxFileDateUPC_CA DATE =
(
	SELECT MAX([File Date])
	FROM HP_MAP_Canada._analysis.MAP_Price_List_Tool_Export_NEW
)

SELECT
	SKU,
	MAX(ISNULL(UPC, '')) AS UPC
INTO #CA_UPC_US
FROM HP_MAP_Canada._analysis.MAP_Price_List_Tool_Export_NEW
WHERE [File Date] = @MaxFileDateUPC_CA
GROUP BY SKU

CREATE UNIQUE CLUSTERED INDEX IX_UPC_US_SKU ON #CA_UPC_US (SKU)

DROP TABLE IF EXISTS #CA_MinViolationDate
SELECT
	New_Location_ID,
	MIN(Collected_Date) AS [Minimum Violation Date]
INTO #CA_MinViolationDate
FROM [HP_MAP_Canada].[_final].[ViolationsMAP]
WHERE Collected_Date >= '2023-11-01'
GROUP BY New_Location_ID

CREATE UNIQUE CLUSTERED INDEX IX_MinViolationDate_Location
	ON #CA_MinViolationDate (New_Location_ID)

-- Use listings for the first and last listing dates.
DROP TABLE IF EXISTS #CA_Min_Max_Listing_Date
SELECT
	s.Master_New_Location_Id,
	MIN(CAST(f.Collected_Date AS DATE)) AS [Minimum Listing Date],
	MAX(CAST(f.Collected_Date AS DATE)) AS [Most Recent Listing Date]
INTO #CA_Min_Max_Listing_Date
FROM HP_MAP_Canada._final.Fact_Listings AS f
INNER JOIN HP_MAP_Canada._final.Dim_Seller AS s
	ON s.Seller_ID = f.Seller_ID
WHERE CAST(f.Collected_Date AS DATE) >= '2023-11-01'
  AND s.Master_New_Location_Id <> 'N/A'
GROUP BY s.Master_New_Location_Id

CREATE UNIQUE CLUSTERED INDEX IX_MinMaxListingDate_Location
	ON #CA_Min_Max_Listing_Date (Master_New_Location_Id)

DROP TABLE IF EXISTS #CA_NewSKU
SELECT DISTINCT SKU
INTO #CA_NewSKU
FROM HP_MAP_Canada._ref.SKU_Enforcement_Exclusion
WHERE Flag_Reporting = 1

CREATE UNIQUE CLUSTERED INDEX IX_NewSKU_SKU ON #CA_NewSKU (SKU)

DROP TABLE IF EXISTS #CA_Grace_Period
SELECT DISTINCT
	CAST('Canada' AS NVARCHAR(10)) AS Country,
	SKU,
	Valid_From,
	Valid_To
INTO #CA_Grace_Period
FROM HP_MAP_Canada._ref.Grace_Period_SKUs

CREATE NONCLUSTERED INDEX IX_GracePeriod_SKU_Dates
	ON #CA_Grace_Period (SKU, Valid_From, Valid_To)

DROP TABLE IF EXISTS #CA_Content
;WITH RankedContent AS
(
	SELECT
		CAST('Canada' AS NVARCHAR(10)) AS Country,
		b.HPI_Location_ID,
		b.Content_Provider AS Content_Source,
		ROW_NUMBER() OVER
		(
			PARTITION BY b.HPI_Location_ID
			ORDER BY b.Create_Date DESC
		) AS RN
	FROM HP_QPP_Prod._WEB.tbl_assessment_form_bg AS b
	WHERE b.Flag_Active = 1
	  AND b.Flag_Current = 1
	  AND b.Country IN ('CA', 'Canada')
)
SELECT
	Country,
	HPI_Location_ID,
	Content_Source
INTO #CA_Content
FROM RankedContent
WHERE RN = 1

CREATE UNIQUE CLUSTERED INDEX IX_Content_Country_Location
	ON #CA_Content (Country, HPI_Location_ID)

-- Read active Canada partners once for both lookups.
DROP TABLE IF EXISTS #CA_ActiveQPP
SELECT
	CONVERT(NVARCHAR(20), p.HPI_Location_ID) AS HPI_Location_ID,
	MAX(p.[Status]) AS Partner_Status,
	MAX(p.Drop_Date) AS Drop_Date,
	MAX(p.Action_Required) AS Action_Required,
	MAX(p.Expiration_Date) AS Expiration_Date
INTO #CA_ActiveQPP
FROM HP_QPP_Prod._web.tbl_Partner AS p
WHERE p.Flag_Active = 1
  AND p.Flag_Current = 1
  AND p.[Status] = 'Active'
  AND p.Country IN ('CA', 'Canada')
GROUP BY CONVERT(NVARCHAR(20), p.HPI_Location_ID)

CREATE UNIQUE CLUSTERED INDEX IX_ActiveQPP_Location
	ON #CA_ActiveQPP (HPI_Location_ID)

DROP TABLE IF EXISTS #CA_PartnerLookup
SELECT
	CONVERT(NVARCHAR(20), p.LocationId) AS LocationId,
	MAX(p.Id) AS Partner_ID
INTO #CA_PartnerLookup
FROM HP_QPP_Prod.dbo.N_Partners AS p
GROUP BY CONVERT(NVARCHAR(20), p.LocationId)

CREATE UNIQUE CLUSTERED INDEX IX_PartnerLookup_Location
	ON #CA_PartnerLookup (LocationId)

-- Use valid notifications for linked details and the latest status.
DROP TABLE IF EXISTS #CA_ValidNotifications
SELECT
	n.ID,
	n.Notification_ID,
	CONVERT(NVARCHAR(20), n.New_Location_ID) AS New_Location_ID,
	CONVERT(NVARCHAR(50), n.Product_Type) AS Product_Type,
	n.Letter_Type,
	n.Generation_Date,
	n.Communication_Sent_Date,
	n.Communication_Delivered_Date,
	n.DGF_Penalty
INTO #CA_ValidNotifications
FROM [HP_MAP_Canada].[_ref].[Notifications_MAP] AS n
WHERE n.Notification_Approval_Status <> 0
  AND ISNULL(n.Wrong_Notification_Flag, 0) = 0
  AND ISNULL(n.Exception_Flag, 0) = 0

CREATE CLUSTERED INDEX IX_ValidNotifications_Location_Product_Generation
	ON #CA_ValidNotifications
	(
		New_Location_ID,
		Product_Type,
		Generation_Date DESC,
		Notification_ID DESC,
		ID DESC
	)

CREATE NONCLUSTERED INDEX IX_ValidNotifications_Notification
	ON #CA_ValidNotifications (Notification_ID, New_Location_ID, Product_Type)
	INCLUDE (Letter_Type, DGF_Penalty)

DROP TABLE IF EXISTS #CA_StoreFrontNames
SELECT
	Country,
	New_Location_ID,
	STRING_AGG(CONVERT(NVARCHAR(MAX), Storefront_Names), '; ')
		WITHIN GROUP (ORDER BY MPA_Date ASC) AS StoreFrontName
INTO #CA_StoreFrontNames
FROM
(
	SELECT DISTINCT
		CONVERT(NVARCHAR(10), Country) AS Country,
		CONVERT(NVARCHAR(20), New_Location_ID) AS New_Location_ID,
		Storefront_Names,
		MPA_Date
	FROM HP_MAP_Prod._ref.Marketplace_Approved
	WHERE Flag_Active = 1
	  AND Flag_Current = 1
	  AND Country = 'Canada'
) AS ApprovedStorefronts
GROUP BY Country, New_Location_ID

CREATE UNIQUE CLUSTERED INDEX IX_StoreFrontNames_Country_Location
	ON #CA_StoreFrontNames (Country, New_Location_ID)

-- Build the Canada violation rows.

DROP TABLE IF EXISTS #CA_ViolationRows
-- Keep every matching product and seller row.
SELECT
	dp.[CSKU_Flag], dp.[Government_SKU_Flag], dp.[In_MAP_Scope_Flag], dp.[Product_Category_Reporting],
	dp.[Product_Description], dp.[Product_Type_Indirect_MAP], dp.[SKU], dp.[Valid_From], dp.[Valid_To]
INTO #MAP_L12M_CA_Product
FROM HP_MAP_Canada._final.Dim_Product AS dp
WHERE dp.Valid_From < DATEADD(DAY, 1, @ThroughDate) AND dp.Valid_To >= @StartDate
  AND dp.In_MAP_Scope_Flag = 'In MAP Scope'
OPTION (MAXDOP 2, RECOMPILE)
CREATE INDEX IX_MAP_L12M_Product ON #MAP_L12M_CA_Product (SKU, Valid_From, Valid_To)
SELECT
	sel.[Master_New_Location_Id], sel.[Print_Qualification], sel.[Qualified_Business_Personal_Systems],
	sel.[Qualified_Consumer_Personal_Systems], sel.[Supplies_Qualification], sel.[Valid_From],
	sel.[Valid_To]
INTO #MAP_L12M_CA_Seller
FROM HP_MAP_Canada._final.Dim_Seller AS sel
WHERE sel.Valid_From < DATEADD(DAY, 1, @ThroughDate) AND sel.Valid_To >= @StartDate
OPTION (MAXDOP 2, RECOMPILE)
CREATE INDEX IX_MAP_L12M_Seller ON #MAP_L12M_CA_Seller (Master_New_Location_Id, Valid_From, Valid_To)
SELECT TOP (0)
	v.[Collected_Date], v.[Comments], v.[Data_Source], v.[Eligible_IR_Amount], v.[Fact_ID],
	v.[Flag_Bundle], v.[HP_Reason_ID], v.[Listing_ID], v.[Login_Type_ID], v.[Lowest_Possible_Price],
	v.[MAP], v.[Market], v.[Market_Unified], v.[Master_SID], v.[New_Location_ID], v.[Notification_ID],
	v.[Price_Location], v.[Product_Page], v.[Product_Type_Enforcement], v.[Reason_ID], v.[Screenshot_URL],
	v.[Seller_Advertised_Price], v.[Seller_Name], v.[Seller_Name_Unified], v.[Seller_Penalty_Type],
	v.[Seller_Reporting_Group], v.[SKU], v.[Tier_Pass_Through], v.[Validation_Status], v.[Violation_Code],
	CONVERT(INT, v.Violation_ID) AS Violation_ID, v.[Week_Start_Date]
INTO #MAP_L12M_CA_Batch
FROM [HP_MAP_Canada].[_final].[ViolationsMAP] AS v
CREATE INDEX IX_MAP_L12M_Batch_SKU ON #MAP_L12M_CA_Batch (SKU, Collected_Date)
SELECT TOP (0) CONVERT(BIGINT, nm.ID) AS ID, nm.ASIN, nm.Listing_URL INTO #MAP_L12M_CA_Listings FROM HP_MAP_Canada._final.Seller_Pricing_NewMo_Canada AS nm
CREATE UNIQUE CLUSTERED INDEX IX_MAP_L12M_Listings ON #MAP_L12M_CA_Listings (ID)
DECLARE @MAP_L12M_CA_BatchStart DATE = @StartDate, @MAP_L12M_CA_BatchEnd DATE = DATEADD(DAY, 1, @StartDate)
SELECT IDENTITY(BIGINT, 1, 1) AS MAP_RowToken, base.* INTO #MAP_L12M_CA_Base
FROM (
	SELECT
		v.Violation_ID,
		v.Fact_ID AS [Fact ID],
		v.Week_Start_Date AS [Week],
		v.Collected_Date AS [Date],
		dp.Product_Category_Reporting AS [Product Category],
		CASE
			WHEN dp.CSKU_Flag = 'C-SKU' THEN 'C-SKU'
			WHEN dp.Government_SKU_Flag = 'Government SKU'
			 AND dp.Product_Category_Reporting = 'Supplies' THEN 'G-SKU'
			ELSE dp.Product_Type_Indirect_MAP
		END AS [Product Subcategory],
		COALESCE
		(
			v.Product_Type_Enforcement,
			CASE
				WHEN dp.Product_Type_Indirect_MAP IN ('Ink', 'Toner') THEN 'Ink & Toner'
				WHEN dp.Product_Type_Indirect_MAP LIKE 'Large Format%' THEN 'Large Format'
				ELSE dp.Product_Type_Indirect_MAP
			END
		) AS [Product Subcategory Enforcement],
		v.SKU,
		UPPER(NULLIF(nm.ASIN, 'N/A')) AS ASIN,
		-- Use the product description from the same date as the category.
		dp.Product_Description AS Product_Description,
		v.Seller_Name_Unified AS Account,
		v.Seller_Name AS [Seller Name],
		v.New_Location_ID AS [Location ID],
		v.Master_SID,
		v.Seller_Penalty_Type AS [Seller Penalty Type],
		v.Seller_Reporting_Group AS [Reporting Group],
		v.Market_Unified AS Market,
		CASE WHEN ISNULL(v.Login_Type_ID, 1) = 3 THEN 'Free log-in' ELSE 'Public Site' END AS [Log-in Type],
		v.Price_Location AS [Price Location],
		v.MAP,
		v.Seller_Advertised_Price AS [Advertised Price],
		v.Eligible_IR_Amount AS [Eligible IR],
		v.Lowest_Possible_Price AS [Lowest Possible Price],
		COALESCE(NULLIF(v.Screenshot_URL, 'N/A'), v.Product_Page, nm.Listing_URL, 'N/A') AS Screenshot_URL,
		ISNULL(v.Validation_Status, 'Not Inspected') AS Validation_Status_Raw,
		COALESCE(hpres.Reason_Description, res.Reason_Description, v.Comments) AS Notes,
		v.Tier_Pass_Through,
		ISNULL(v.Flag_Bundle, 0) AS Flag_Bundle,
		ISNULL(v.Login_Type_ID, 1) AS Login_Type_ID,
		CASE WHEN v.Violation_Code = 8 THEN 1 ELSE 0 END AS Flag_StrikeThrough,
		CASE
			WHEN v.Violation_Code = 6 THEN 'C-SKU - Restricted'
			WHEN v.Violation_Code = 8 THEN 'Strike-through'
			WHEN v.Violation_Code = 9 THEN 'Price - Coupon'
			WHEN v.Flag_Bundle = 1 THEN 'Price - Bundle'
			WHEN v.Price_Location IN ('Product Page Ad', 'Product Page') THEN 'Price - Product Page'
			WHEN v.Price_Location = 'Shopping Cart' THEN 'Price - In-Cart'
			ELSE 'Electronic Content'
		END AS Violation_Type,
		CASE
			WHEN v.Market = 'Websites Canada'
			  OR (v.Market = 'Amazon Canada' AND v.New_Location_ID = '10241372')
			  OR (v.Market = 'Newegg Canada' AND v.New_Location_ID = '10248471')
			  OR (v.Market = 'Walmart Canada' AND v.New_Location_ID = '10292113') THEN 1
			WHEN v.Market = 'Amazon Canada' THEN 2
			WHEN v.Market = 'Walmart Canada' THEN 3
			WHEN v.Market = 'Ebay Canada' THEN 4
			WHEN v.Market = 'Newegg Canada' THEN 5
			WHEN v.Market = 'Best Buy Canada' THEN 6
			ELSE 7
		END AS Market_ID,
		CASE
			WHEN qpp.HPI_Location_ID IS NOT NULL
				THEN HP_MAP_Prod.dbo.FN_GET_SELLER_STATUS
				(
					dp.Product_Category_Reporting,
					sel.Supplies_Qualification,
					sel.Print_Qualification,
					sel.Qualified_Business_Personal_Systems,
					sel.Qualified_Consumer_Personal_Systems
				)
			ELSE 'Unauthorized'
		END AS Seller_Status,
		CASE
			WHEN qpp.Partner_Status = 'Dropped' THEN qpp.Drop_Date
			WHEN qpp.Action_Required = 'PA Termination' THEN qpp.Expiration_Date
			ELSE NULL
		END AS [Termination Date],
		v.Notification_ID,
		linked_notification.DGF_Penalty,
		CASE
			WHEN v.Validation_Status = 'Accepted'
			 AND LEFT(linked_notification.Letter_Type, 1) = 'W' THEN 1
			ELSE 0
		END AS Flag_Triggered_Warning
	FROM #MAP_L12M_CA_Batch AS v
	-- Use the product details in effect on the violation date.
	INNER JOIN #MAP_L12M_CA_Product AS dp
		ON dp.SKU = v.SKU
	   AND v.Collected_Date BETWEEN dp.Valid_From AND dp.Valid_To
	   AND dp.In_MAP_Scope_Flag = 'In MAP Scope'
	INNER JOIN #MAP_L12M_CA_Seller AS sel
		ON sel.Master_New_Location_Id = v.New_Location_ID
	   AND v.Collected_Date BETWEEN sel.Valid_From AND sel.Valid_To
	LEFT JOIN #MAP_L12M_CA_Listings AS nm
		ON nm.ID = v.Listing_ID
	   -- Look up Pervasive Mind listings in NewMo.
	   AND v.Data_Source IN ('NewMo', 'Pervasive Mind')
	LEFT JOIN HP_MAP_Canada._ref.Rejection_Reasons AS res
		ON res.Reason_ID = v.Reason_ID
	LEFT JOIN HP_MAP_Canada._ref.HP_Rejection_Reasons AS hpres
		ON hpres.HP_Reason_ID = v.HP_Reason_ID
	LEFT JOIN #CA_ActiveQPP AS qpp
		ON qpp.HPI_Location_ID = v.New_Location_ID
	OUTER APPLY
	(
		SELECT TOP (1)
			n.Letter_Type,
			n.DGF_Penalty
		FROM #CA_ValidNotifications AS n
		WHERE n.Notification_ID = v.Notification_ID
		  AND n.New_Location_ID = v.New_Location_ID
		  AND n.Product_Type = v.Product_Type_Enforcement
		ORDER BY n.Generation_Date DESC, n.ID DESC
	) AS linked_notification
	WHERE v.Collected_Date >= @MAP_L12M_CA_BatchStart
	  AND v.Collected_Date < @MAP_L12M_CA_BatchEnd    -- 4/6/20 LU: due to intraday launch, need to restrict violations from current date
	  AND (qpp.HPI_Location_ID IS NOT NULL OR v.New_Location_ID = '99999999')
) AS base WHERE 1 = 0
CREATE UNIQUE CLUSTERED INDEX IX_MAP_L12M_Base_Token ON #MAP_L12M_CA_Base (MAP_RowToken)
WHILE @MAP_L12M_CA_BatchStart <= @ThroughDate
BEGIN
	TRUNCATE TABLE #MAP_L12M_CA_Batch
	TRUNCATE TABLE #MAP_L12M_CA_Listings
	INSERT INTO #MAP_L12M_CA_Batch
	(
		[Collected_Date], [Comments], [Data_Source], [Eligible_IR_Amount], [Fact_ID], [Flag_Bundle],
		[HP_Reason_ID], [Listing_ID], [Login_Type_ID], [Lowest_Possible_Price], [MAP], [Market],
		[Market_Unified], [Master_SID], [New_Location_ID], [Notification_ID], [Price_Location], [Product_Page],
		[Product_Type_Enforcement], [Reason_ID], [Screenshot_URL], [Seller_Advertised_Price], [Seller_Name],
		[Seller_Name_Unified], [Seller_Penalty_Type], [Seller_Reporting_Group], [SKU], [Tier_Pass_Through],
		[Validation_Status], [Violation_Code], [Violation_ID], [Week_Start_Date]
	)
	SELECT
		v.[Collected_Date], v.[Comments], v.[Data_Source], v.[Eligible_IR_Amount], v.[Fact_ID],
		v.[Flag_Bundle], v.[HP_Reason_ID], v.[Listing_ID], v.[Login_Type_ID], v.[Lowest_Possible_Price],
		v.[MAP], v.[Market], v.[Market_Unified], v.[Master_SID], v.[New_Location_ID], v.[Notification_ID],
		v.[Price_Location], v.[Product_Page], v.[Product_Type_Enforcement], v.[Reason_ID], v.[Screenshot_URL],
		v.[Seller_Advertised_Price], v.[Seller_Name], v.[Seller_Name_Unified], v.[Seller_Penalty_Type],
		v.[Seller_Reporting_Group], v.[SKU], v.[Tier_Pass_Through], v.[Validation_Status], v.[Violation_Code],
		v.[Violation_ID], v.[Week_Start_Date]
	FROM [HP_MAP_Canada].[_final].[ViolationsMAP] AS v
	WHERE v.Collected_Date >= @MAP_L12M_CA_BatchStart AND v.Collected_Date < @MAP_L12M_CA_BatchEnd
	OPTION (MAXDOP 2, RECOMPILE)
	-- Look up each listing once per batch.
	INSERT INTO #MAP_L12M_CA_Listings (ID, ASIN, Listing_URL)
	SELECT nm.ID, nm.ASIN, nm.Listing_URL
	FROM (SELECT DISTINCT Listing_ID FROM #MAP_L12M_CA_Batch
		  WHERE Data_Source IN ('NewMo', 'Pervasive Mind') AND Listing_ID IS NOT NULL) AS keys_needed
	INNER LOOP JOIN HP_MAP_Canada._final.Seller_Pricing_NewMo_Canada AS nm WITH (INDEX([NonClusteredIndex-20191217-072548])) ON nm.ID = keys_needed.Listing_ID
	OPTION (MAXDOP 2, RECOMPILE)
	INSERT INTO #MAP_L12M_CA_Base
	(
		[Violation_ID], [Fact ID], [Week], [Date], [Product Category], [Product Subcategory],
		[Product Subcategory Enforcement], [SKU], [ASIN], [Product_Description], [Account], [Seller Name],
		[Location ID], [Master_SID], [Seller Penalty Type], [Reporting Group], [Market], [Log-in Type],
		[Price Location], [MAP], [Advertised Price], [Eligible IR], [Lowest Possible Price], [Screenshot_URL],
		[Validation_Status_Raw], [Notes], [Tier_Pass_Through], [Flag_Bundle], [Login_Type_ID],
		[Flag_StrikeThrough], [Violation_Type], [Market_ID], [Seller_Status], [Termination Date],
		[Notification_ID], [DGF_Penalty], [Flag_Triggered_Warning]
	)
	SELECT
		v.Violation_ID,
		v.Fact_ID AS [Fact ID],
		v.Week_Start_Date AS [Week],
		v.Collected_Date AS [Date],
		dp.Product_Category_Reporting AS [Product Category],
		CASE
			WHEN dp.CSKU_Flag = 'C-SKU' THEN 'C-SKU'
			WHEN dp.Government_SKU_Flag = 'Government SKU'
			 AND dp.Product_Category_Reporting = 'Supplies' THEN 'G-SKU'
			ELSE dp.Product_Type_Indirect_MAP
		END AS [Product Subcategory],
		COALESCE
		(
			v.Product_Type_Enforcement,
			CASE
				WHEN dp.Product_Type_Indirect_MAP IN ('Ink', 'Toner') THEN 'Ink & Toner'
				WHEN dp.Product_Type_Indirect_MAP LIKE 'Large Format%' THEN 'Large Format'
				ELSE dp.Product_Type_Indirect_MAP
			END
		) AS [Product Subcategory Enforcement],
		v.SKU,
		UPPER(NULLIF(nm.ASIN, 'N/A')) AS ASIN,
		-- Use the product description from the same date as the category.
		dp.Product_Description AS Product_Description,
		v.Seller_Name_Unified AS Account,
		v.Seller_Name AS [Seller Name],
		v.New_Location_ID AS [Location ID],
		v.Master_SID,
		v.Seller_Penalty_Type AS [Seller Penalty Type],
		v.Seller_Reporting_Group AS [Reporting Group],
		v.Market_Unified AS Market,
		CASE WHEN ISNULL(v.Login_Type_ID, 1) = 3 THEN 'Free log-in' ELSE 'Public Site' END AS [Log-in Type],
		v.Price_Location AS [Price Location],
		v.MAP,
		v.Seller_Advertised_Price AS [Advertised Price],
		v.Eligible_IR_Amount AS [Eligible IR],
		v.Lowest_Possible_Price AS [Lowest Possible Price],
		COALESCE(NULLIF(v.Screenshot_URL, 'N/A'), v.Product_Page, nm.Listing_URL, 'N/A') AS Screenshot_URL,
		ISNULL(v.Validation_Status, 'Not Inspected') AS Validation_Status_Raw,
		COALESCE(hpres.Reason_Description, res.Reason_Description, v.Comments) AS Notes,
		v.Tier_Pass_Through,
		ISNULL(v.Flag_Bundle, 0) AS Flag_Bundle,
		ISNULL(v.Login_Type_ID, 1) AS Login_Type_ID,
		CASE WHEN v.Violation_Code = 8 THEN 1 ELSE 0 END AS Flag_StrikeThrough,
		CASE
			WHEN v.Violation_Code = 6 THEN 'C-SKU - Restricted'
			WHEN v.Violation_Code = 8 THEN 'Strike-through'
			WHEN v.Violation_Code = 9 THEN 'Price - Coupon'
			WHEN v.Flag_Bundle = 1 THEN 'Price - Bundle'
			WHEN v.Price_Location IN ('Product Page Ad', 'Product Page') THEN 'Price - Product Page'
			WHEN v.Price_Location = 'Shopping Cart' THEN 'Price - In-Cart'
			ELSE 'Electronic Content'
		END AS Violation_Type,
		CASE
			WHEN v.Market = 'Websites Canada'
			  OR (v.Market = 'Amazon Canada' AND v.New_Location_ID = '10241372')
			  OR (v.Market = 'Newegg Canada' AND v.New_Location_ID = '10248471')
			  OR (v.Market = 'Walmart Canada' AND v.New_Location_ID = '10292113') THEN 1
			WHEN v.Market = 'Amazon Canada' THEN 2
			WHEN v.Market = 'Walmart Canada' THEN 3
			WHEN v.Market = 'Ebay Canada' THEN 4
			WHEN v.Market = 'Newegg Canada' THEN 5
			WHEN v.Market = 'Best Buy Canada' THEN 6
			ELSE 7
		END AS Market_ID,
		CASE
			WHEN qpp.HPI_Location_ID IS NOT NULL
				THEN HP_MAP_Prod.dbo.FN_GET_SELLER_STATUS
				(
					dp.Product_Category_Reporting,
					sel.Supplies_Qualification,
					sel.Print_Qualification,
					sel.Qualified_Business_Personal_Systems,
					sel.Qualified_Consumer_Personal_Systems
				)
			ELSE 'Unauthorized'
		END AS Seller_Status,
		CASE
			WHEN qpp.Partner_Status = 'Dropped' THEN qpp.Drop_Date
			WHEN qpp.Action_Required = 'PA Termination' THEN qpp.Expiration_Date
			ELSE NULL
		END AS [Termination Date],
		v.Notification_ID,
		linked_notification.DGF_Penalty,
		CASE
			WHEN v.Validation_Status = 'Accepted'
			 AND LEFT(linked_notification.Letter_Type, 1) = 'W' THEN 1
			ELSE 0
		END AS Flag_Triggered_Warning
	FROM #MAP_L12M_CA_Batch AS v
	-- Use the product details in effect on the violation date.
	INNER JOIN #MAP_L12M_CA_Product AS dp
		ON dp.SKU = v.SKU
	   AND v.Collected_Date BETWEEN dp.Valid_From AND dp.Valid_To
	   AND dp.In_MAP_Scope_Flag = 'In MAP Scope'
	INNER JOIN #MAP_L12M_CA_Seller AS sel
		ON sel.Master_New_Location_Id = v.New_Location_ID
	   AND v.Collected_Date BETWEEN sel.Valid_From AND sel.Valid_To
	LEFT JOIN #MAP_L12M_CA_Listings AS nm
		ON nm.ID = v.Listing_ID
	   -- Look up Pervasive Mind listings in NewMo.
	   AND v.Data_Source IN ('NewMo', 'Pervasive Mind')
	LEFT JOIN HP_MAP_Canada._ref.Rejection_Reasons AS res
		ON res.Reason_ID = v.Reason_ID
	LEFT JOIN HP_MAP_Canada._ref.HP_Rejection_Reasons AS hpres
		ON hpres.HP_Reason_ID = v.HP_Reason_ID
	LEFT JOIN #CA_ActiveQPP AS qpp
		ON qpp.HPI_Location_ID = v.New_Location_ID
	OUTER APPLY
	(
		SELECT TOP (1)
			n.Letter_Type,
			n.DGF_Penalty
		FROM #CA_ValidNotifications AS n
		WHERE n.Notification_ID = v.Notification_ID
		  AND n.New_Location_ID = v.New_Location_ID
		  AND n.Product_Type = v.Product_Type_Enforcement
		ORDER BY n.Generation_Date DESC, n.ID DESC
	) AS linked_notification
	WHERE v.Collected_Date >= @MAP_L12M_CA_BatchStart
	  AND v.Collected_Date < @MAP_L12M_CA_BatchEnd    -- 4/6/20 LU: due to intraday launch, need to restrict violations from current date
	  AND (qpp.HPI_Location_ID IS NOT NULL OR v.New_Location_ID = '99999999')
	OPTION (MAXDOP 2, RECOMPILE)
	SET @MAP_L12M_CA_BatchStart = @MAP_L12M_CA_BatchEnd
	SET @MAP_L12M_CA_BatchEnd = DATEADD(DAY, 1, @MAP_L12M_CA_BatchStart)
END
-- Calculate selectors before joining the wider report fields.
SELECT base.MAP_RowToken,
	MAX(CASE WHEN base.Validation_Status_Raw = 'Accepted' THEN 1 ELSE 0 END)
		OVER (PARTITION BY base.[Week], base.[Location ID], base.SKU, base.Login_Type_ID) AS Has_Accepted,
	MAX(CASE WHEN base.Validation_Status_Raw = 'Rejected' THEN 1 ELSE 0 END)
		OVER (PARTITION BY base.[Week], base.[Location ID], base.SKU, base.Login_Type_ID) AS Has_Rejected,
	ROW_NUMBER() OVER (PARTITION BY base.[Location ID], base.[Date], base.SKU, base.Login_Type_ID
		ORDER BY base.Flag_Triggered_Warning DESC,
			REPLACE(ISNULL(base.Validation_Status_Raw, 'Z'), 'Not Inspected', 'Z'),
			base.Market_ID, base.Violation_ID) AS Violation_ID_Selector
INTO #MAP_L12M_CA_Signals FROM #MAP_L12M_CA_Base AS base
OPTION (MAXDOP 2, RECOMPILE)
CREATE UNIQUE CLUSTERED INDEX IX_MAP_L12M_Signals ON #MAP_L12M_CA_Signals (MAP_RowToken)
SELECT
	base.[Violation_ID], base.[Fact ID], base.[Week], base.[Date], base.[Product Category],
	base.[Product Subcategory], base.[Product Subcategory Enforcement], base.[SKU], base.[ASIN],
	base.[Product_Description], base.[Account], base.[Seller Name], base.[Location ID], base.[Master_SID],
	base.[Seller Penalty Type], base.[Reporting Group], base.[Market], base.[Log-in Type],
	base.[Price Location], base.[MAP], base.[Advertised Price], base.[Eligible IR],
	base.[Lowest Possible Price], base.[Screenshot_URL], base.[Validation_Status_Raw], base.[Notes],
	base.[Tier_Pass_Through], base.[Flag_Bundle], base.[Login_Type_ID], base.[Flag_StrikeThrough],
	base.[Violation_Type], base.[Market_ID], base.[Seller_Status], base.[Termination Date],
	base.[Notification_ID], base.[DGF_Penalty], base.[Flag_Triggered_Warning], signal.Has_Accepted,
	signal.Has_Rejected,
	CASE WHEN base.Validation_Status_Raw = 'Not Inspected' AND signal.Has_Accepted = 1 THEN 'Accepted - Derived'
		 WHEN base.Validation_Status_Raw = 'Not Inspected' AND signal.Has_Rejected = 1 THEN 'Rejected - Derived'
		 ELSE base.Validation_Status_Raw END AS [Validation Status],
	CASE WHEN signal.Has_Accepted = 1 THEN 'Accepted' WHEN signal.Has_Rejected = 1 THEN 'Rejected'
		 ELSE base.Validation_Status_Raw END AS [Validation Status Weekly],
	signal.Violation_ID_Selector
INTO #CA_ViolationRows
FROM #MAP_L12M_CA_Base AS base INNER JOIN #MAP_L12M_CA_Signals AS signal ON signal.MAP_RowToken = base.MAP_RowToken
WHERE signal.Violation_ID_Selector = 1
OPTION (MAXDOP 2, RECOMPILE)
DROP TABLE #MAP_L12M_CA_Signals, #MAP_L12M_CA_Base, #MAP_L12M_CA_Listings, #MAP_L12M_CA_Batch, #MAP_L12M_CA_Product, #MAP_L12M_CA_Seller

CREATE NONCLUSTERED INDEX IX_ViolationRows_Location_Product_Date
	ON #CA_ViolationRows ([Location ID], [Product Subcategory], [Date])
	INCLUDE (Master_SID, SKU, Login_Type_ID, Notification_ID)

DROP TABLE IF EXISTS #CA_Sellers
;WITH RankedSellers AS
(
	SELECT
		v.Account,
		v.[Location ID],
		v.Master_SID,
		ROW_NUMBER() OVER
		(
			PARTITION BY v.[Location ID]
			ORDER BY v.[Date] DESC, v.Violation_ID DESC
		) AS RN
	FROM #CA_ViolationRows AS v
)
SELECT
	Account,
	[Location ID],
	Master_SID
INTO #CA_Sellers
FROM RankedSellers
WHERE RN = 1

CREATE UNIQUE CLUSTERED INDEX IX_Sellers_Location ON #CA_Sellers ([Location ID])

-- Use top-seller list membership for the flag.
DROP TABLE IF EXISTS #CA_TopResellers
SELECT DISTINCT
	CONVERT(NVARCHAR(20), top_seller.Master_New_Location_Id) AS New_Location_ID
INTO #CA_TopResellers
FROM HP_MAP_Canada._ref.Courtesy_Alerts_Top_Seller_List AS top_seller
INNER JOIN #CA_Sellers AS seller
	ON seller.[Location ID] = top_seller.Master_New_Location_Id
WHERE top_seller.Master_New_Location_Id IS NOT NULL

CREATE UNIQUE CLUSTERED INDEX IX_TopResellers_Location
	ON #CA_TopResellers (New_Location_ID)

-- Read strike details once for report sellers.
DROP TABLE IF EXISTS #CA_ValidStrikes
SELECT
	s.ID,
	s.Notification_ID,
	CONVERT(NVARCHAR(20), s.New_Location_ID) AS New_Location_ID,
	CONVERT(NVARCHAR(50), s.Product_Type) AS Product_Type,
	s.Violation_Status,
	s.Flag_Is_Active,
	s.Flag_Rehab,
	s.Flag_Cancelled,
	s.Buffer_Period_Start_Date,
	s.Buffer_Period_End_Date,
	s.Penalty_Period_Start_Date,
	s.Penalty_Period_End_Date_Adjusted,
	s.Product_Suspension_Start_Date,
	s.Product_Suspension_End_Date,
	s.Valid_From
INTO #CA_ValidStrikes
FROM [HP_MAP_Canada].[dbo].[VI_MAP_Strikes_History] AS s
INNER JOIN #CA_Sellers AS seller
	ON seller.[Location ID] = s.New_Location_ID
WHERE ISNULL(s.Flag_Cancelled, 0) = 0
  AND EXISTS
  (
	  SELECT 1
	  FROM #CA_ValidNotifications AS n
	  WHERE n.Notification_ID = s.Notification_ID
		AND n.New_Location_ID = s.New_Location_ID
		AND n.Product_Type = s.Product_Type
  )
OPTION (RECOMPILE)

CREATE CLUSTERED INDEX IX_ValidStrikes_Location_Product_Period
	ON #CA_ValidStrikes
	(
		New_Location_ID,
		Product_Type,
		Penalty_Period_Start_Date,
		Penalty_Period_End_Date_Adjusted
	)

CREATE NONCLUSTERED INDEX IX_ValidStrikes_Notification
	ON #CA_ValidStrikes (Notification_ID, New_Location_ID, Product_Type)
	INCLUDE
	(
		ID,
		Violation_Status,
		Flag_Is_Active,
		Flag_Rehab,
		Buffer_Period_Start_Date,
		Buffer_Period_End_Date,
		Penalty_Period_Start_Date,
		Penalty_Period_End_Date_Adjusted,
		Product_Suspension_Start_Date,
		Product_Suspension_End_Date,
		Valid_From
	)

-- Use the latest valid notification for each seller and product.
DROP TABLE IF EXISTS #CA_LatestNotifications
;WITH RankedNotifications AS
(
	SELECT
		n.ID,
		n.Notification_ID,
		n.New_Location_ID,
		n.Product_Type,
		n.Letter_Type,
		n.Generation_Date,
		n.Communication_Sent_Date,
		n.Communication_Delivered_Date,
		n.DGF_Penalty,
		ROW_NUMBER() OVER
		(
			PARTITION BY n.New_Location_ID, n.Product_Type
			ORDER BY n.Generation_Date DESC, n.Notification_ID DESC, n.ID DESC
		) AS RN
	FROM #CA_ValidNotifications AS n
	INNER JOIN #CA_Sellers AS seller
		ON seller.[Location ID] = n.New_Location_ID
)
SELECT
	ID,
	Notification_ID,
	New_Location_ID,
	Product_Type,
	Letter_Type,
	Generation_Date,
	Communication_Sent_Date,
	Communication_Delivered_Date,
	DGF_Penalty
INTO #CA_LatestNotifications
FROM RankedNotifications
WHERE RN = 1

CREATE UNIQUE CLUSTERED INDEX IX_LatestNotifications_Location_Product
	ON #CA_LatestNotifications (New_Location_ID, Product_Type)

DROP TABLE IF EXISTS #CA_LatestStrikes
;WITH RankedLatestStrikes AS
(
	SELECT
		s.*,
		ROW_NUMBER() OVER
		(
			PARTITION BY s.New_Location_ID, s.Product_Type
			ORDER BY s.Valid_From DESC, s.ID DESC
		) AS RN
	FROM #CA_ValidStrikes AS s
	INNER JOIN #CA_LatestNotifications AS n
		ON n.Notification_ID = s.Notification_ID
	   AND n.New_Location_ID = s.New_Location_ID
	   AND n.Product_Type = s.Product_Type
)
SELECT
	ID,
	Notification_ID,
	New_Location_ID,
	Product_Type,
	Flag_Is_Active,
	Flag_Rehab,
	Buffer_Period_Start_Date,
	Buffer_Period_End_Date,
	Penalty_Period_Start_Date,
	Penalty_Period_End_Date_Adjusted,
	Product_Suspension_Start_Date,
	Product_Suspension_End_Date
INTO #CA_LatestStrikes
FROM RankedLatestStrikes
WHERE RN = 1

CREATE UNIQUE CLUSTERED INDEX IX_LatestStrikes_Location_Product
	ON #CA_LatestStrikes (New_Location_ID, Product_Type)

-- Include the calendar, products and sellers needed by Tableau.
DROP TABLE IF EXISTS #CA_CTE_cj
SELECT
	w.[Week],
	w.[Date],
	p.[Product Category],
	p.[Product Subcategory],
	CASE WHEN p.[Rule Product Type] = 'Large Format Supplies' AND rg.Penalty_Type LIKE '%Financial%'
		 THEN 'Large Format Supplies' ELSE p.[Product Subcategory Enforcement] END AS [Product Subcategory Enforcement],
	p.[Rule Product Type],
	s.Account,
	ISNULL(LEFT(sf.StoreFrontName, 4000), 'Seller not Marketplace Approved') AS [Storefront Name(s)], -- 3/20 LU added for Storefront Name(s)
	s.[Location ID],
	s.Master_SID,
	ISNULL(rg.Penalty_Type, '30, 60, 90 Suspension') AS [Seller Penalty Type],
	ISNULL(rg.Reporting_Group, 'All') AS [Reporting Group]   -- 3/6 LU Added for MPA Reporting Group
INTO #CA_CTE_cj
FROM #Weeks AS w
CROSS JOIN #CA_Product_Category AS p
CROSS JOIN #CA_Sellers AS s
LEFT JOIN #CA_StoreFrontNames AS sf
	ON sf.New_Location_ID = s.[Location ID]
   AND sf.Country = 'Canada'
OUTER APPLY
(
	SELECT TOP (1) r.Penalty_Type, r.Reporting_Group
	FROM [HP_MAP_Canada].[_ref].[Seller_Reporting_Group] AS r
	WHERE r.Product_Type = p.[Rule Product Type]
	  AND w.[Date] BETWEEN r.Valid_From AND r.Valid_To
	  AND (r.Master_SID = s.Master_SID OR (r.Master_SID = -9999 AND NOT EXISTS
		  (SELECT 1 FROM [HP_MAP_Canada].[_ref].[Seller_Reporting_Group] AS named_policy
		   WHERE named_policy.Master_SID = s.Master_SID AND named_policy.Product_Type = p.[Rule Product Type]
			 AND w.[Date] BETWEEN named_policy.Valid_From AND named_policy.Valid_To)))
	ORDER BY r.Valid_From DESC, r.ID DESC
) AS rg

CREATE NONCLUSTERED INDEX IX_CTE_cj_Location_Product_Date
	ON #CA_CTE_cj ([Location ID], [Product Subcategory], [Date])
	INCLUDE (Master_SID, [Week], [Product Subcategory Enforcement])

-- Read each contact view once for the seller email lookups.
DROP TABLE IF EXISTS #CA_SellerEmailInfo
SELECT DISTINCT
	CONVERT(NVARCHAR(20), i.New_Location_ID) AS New_Location_ID,
	CAST('All' AS NVARCHAR(100)) AS Product_Type,
	CONVERT(NVARCHAR(100), i.Product_Category) AS Product_Category,
	LOWER(CONVERT(NVARCHAR(255), i.HP_Rep_1_Email)) AS Email1,
	LOWER(CONVERT(NVARCHAR(255), i.HP_Rep_2_Email)) AS Email2,
	LOWER(CONVERT(NVARCHAR(255), i.HP_Rep_3_Email)) AS Email3,
	LOWER(CONVERT(NVARCHAR(255), i.HP_Rep_4_Email)) AS Email4,
	LOWER(CONVERT(NVARCHAR(255), i.HP_Rep_5_Email)) AS Email5,
	LOWER(CONVERT(NVARCHAR(255), i.HP_Rep_6_Email)) AS Email6
INTO #CA_SellerEmailInfo
FROM HP_MAP_Canada.dbo.VI_SELLERS_EMAIL_INFO_ALL AS i
INNER JOIN #CA_Sellers AS seller
	ON seller.[Location ID] = i.New_Location_ID
WHERE i.Source_Rank = 1
OPTION (RECOMPILE)

CREATE NONCLUSTERED INDEX IX_SellerEmailInfo_Location
	ON #CA_SellerEmailInfo (New_Location_ID)
	INCLUDE (Product_Type, Product_Category, Email1, Email2, Email3, Email4, Email5, Email6)

DROP TABLE IF EXISTS #CA_SellerEmailUnion
SELECT
	LOWER(CONVERT(NVARCHAR(255), email_source.Email)) AS Email,
	MAX(CONVERT(NVARCHAR(255), email_source.Rep)) AS Rep
INTO #CA_SellerEmailUnion
FROM HP_MAP_Prod._report.Seller_Email_Union AS email_source
WHERE email_source.Email IS NOT NULL
GROUP BY LOWER(CONVERT(NVARCHAR(255), email_source.Email))
OPTION (RECOMPILE)

CREATE UNIQUE CLUSTERED INDEX IX_SellerEmailUnion_Email
	ON #CA_SellerEmailUnion (Email)

DROP TABLE IF EXISTS #CA_ContactBase
;WITH ContactCandidates AS
(
	SELECT
		seller.Account AS [Seller Name Unified],
		seller.[Location ID] AS [New Location ID],
		product.[Product Category],
		i.Email1,
		i.Email2,
		i.Email3,
		i.Email4,
		i.Email5,
		i.Email6,
		ROW_NUMBER() OVER
		(
			PARTITION BY seller.[Location ID], product.[Product Category]
			-- Use the contact order to pick one email.
			ORDER BY
				i.Email1,
				i.Email2,
				i.Email3,
				i.Email4,
				i.Email5,
				i.Email6,
				i.Product_Type,
				i.Product_Category
		) AS RN
	FROM #CA_Sellers AS seller
	CROSS JOIN
	(
		SELECT DISTINCT
			CASE
				WHEN [Product Subcategory] LIKE 'Large Format%' THEN 'Large Format'
				ELSE [Product Category]
			END AS [Product Category]
		FROM #CA_Product_Category
	) AS product
	LEFT JOIN #CA_SellerEmailInfo AS i
		ON i.New_Location_ID = seller.[Location ID]
	   AND i.Product_Category = CASE WHEN product.[Product Category] IN ('CPS', 'BPS') THEN 'PC' ELSE product.[Product Category] END
)
SELECT
	[Seller Name Unified],
	[New Location ID],
	[Product Category],
	Email1,
	Email2,
	Email3,
	Email4,
	Email5,
	Email6
INTO #CA_ContactBase
FROM ContactCandidates
WHERE RN = 1

DROP TABLE IF EXISTS #CA_CTE_Contacts
SELECT
	contact.[Seller Name Unified],
	contact.[New Location ID],
	contact.[Product Category],
	MAX(CASE WHEN email_slot.Slot = 1 THEN rep.Rep END) AS HP_Rep1,
	MAX(CASE WHEN email_slot.Slot = 2 THEN rep.Rep END) AS HP_Rep2,
	MAX(CASE WHEN email_slot.Slot = 3 THEN rep.Rep END) AS HP_Rep3,
	MAX(CASE WHEN email_slot.Slot = 4 THEN rep.Rep END) AS HP_Rep4,
	MAX(CASE WHEN email_slot.Slot = 5 THEN rep.Rep END) AS HP_Rep5,
	MAX(CASE WHEN email_slot.Slot = 6 THEN rep.Rep END) AS HP_Rep6,
	MAX(CASE WHEN email_slot.Slot = 1 THEN email_slot.Email END) AS Email1,
	MAX(CASE WHEN email_slot.Slot = 2 THEN email_slot.Email END) AS Email2,
	MAX(CASE WHEN email_slot.Slot = 3 THEN email_slot.Email END) AS Email3,
	MAX(CASE WHEN email_slot.Slot = 4 THEN email_slot.Email END) AS Email4,
	MAX(CASE WHEN email_slot.Slot = 5 THEN email_slot.Email END) AS Email5,
	MAX(CASE WHEN email_slot.Slot = 6 THEN email_slot.Email END) AS Email6
INTO #CA_CTE_Contacts
FROM #CA_ContactBase AS contact
CROSS APPLY
(
	VALUES
		(1, contact.Email1),
		(2, contact.Email2),
		(3, contact.Email3),
		(4, contact.Email4),
		(5, contact.Email5),
		(6, contact.Email6)
) AS email_slot (Slot, Email)
LEFT JOIN #CA_SellerEmailUnion AS rep
	ON rep.Email = email_slot.Email
GROUP BY
	contact.[Seller Name Unified],
	contact.[New Location ID],
	contact.[Product Category]

CREATE UNIQUE CLUSTERED INDEX IX_CTE_Contacts_Location_Category
	ON #CA_CTE_Contacts ([New Location ID], [Product Category])

-- Build the Canada report rows.
DROP TABLE IF EXISTS #CA_OutputBase
SELECT
	CAST('Canada' AS NVARCHAR(10)) AS Country,
	violation.[Validation Status],
	violation.[Validation Status Weekly],
	fiscal.Fiscal_Week_Number AS [Fiscal Week Number],
	scaffold.[Week],
	scaffold.[Date],
	scaffold.[Product Category],
	scaffold.[Product Subcategory],
	scaffold.[Product Subcategory Enforcement],
	CONVERT(BIGINT, violation.[Fact ID]) AS [Fact ID],
	violation.SKU,
	CONVERT(NVARCHAR(4000), violation.ASIN) AS ASIN,
	CONVERT(NVARCHAR(300), LEFT(violation.Product_Description, 300)) AS Product_Description,
	CONVERT
	(
		NVARCHAR(300),
		LEFT
		(
			scaffold.Account,
			300
		)
	) AS Account,
	CONVERT(NVARCHAR(300), LEFT(violation.[Seller Name], 300)) AS [Seller Name],
	CONVERT(NVARCHAR(4000), scaffold.[Storefront Name(s)]) AS [Storefront Name(s)], -- 3/20 LU Adding StoreFront Name(s)
	CONVERT(NVARCHAR(255), LEFT(scaffold.[Location ID], 255)) AS [Location ID],
	CONVERT
	(
		NVARCHAR(20),
		LEFT
		(
			CASE
				WHEN scaffold.[Location ID] = '99999999' THEN 'Qualified'
				WHEN qpp.HPI_Location_ID IS NOT NULL
					THEN HP_MAP_Prod.dbo.FN_GET_SELLER_STATUS
					(
						scaffold.[Product Category],
						seller_at_date.Supplies_Qualification,
						seller_at_date.Print_Qualification,
						seller_at_date.Qualified_Business_Personal_Systems,
						seller_at_date.Qualified_Consumer_Personal_Systems
					)
				ELSE 'Unauthorized'
			END,
			20
		)
	) AS [Seller Status],
	CONVERT
	(
		DATETIME,
		CASE
			WHEN qpp.Partner_Status = 'Dropped' THEN qpp.Drop_Date
			WHEN qpp.Action_Required = 'PA Termination' THEN qpp.Expiration_Date
			ELSE NULL
		END
	) AS [Termination Date],
	CONVERT(NVARCHAR(40), LEFT(COALESCE(violation.[Seller Penalty Type], scaffold.[Seller Penalty Type]), 40)) AS [Seller Penalty Type],
	CONVERT(NVARCHAR(40), LEFT(COALESCE(violation.[Reporting Group], scaffold.[Reporting Group], 'All'), 40)) AS [Reporting Group], -- 3/6 LU Added for MPA Reporting Group
	CONVERT(NVARCHAR(255), LEFT(violation.Market, 255)) AS Market,
	CONVERT(NVARCHAR(255), LEFT(violation.[Log-in Type], 255)) AS [Log-in Type],
	CONVERT(NVARCHAR(255), LEFT(violation.[Price Location], 255)) AS [Price Location],
	CONVERT(NUMERIC(19, 4), violation.MAP) AS MAP,
	CONVERT(NUMERIC(19, 4), violation.[Advertised Price]) AS [Advertised Price],
	CONVERT(NUMERIC(19, 4), violation.[Eligible IR]) AS [Eligible IR],
	CONVERT(NUMERIC(19, 4), violation.[Lowest Possible Price]) AS [Lowest Possible Price],
	CONVERT(NVARCHAR(255), LEFT(violation.Validation_Status_Raw, 255)) AS Validation_Status_Raw,
	CONVERT(NVARCHAR(255), LEFT(latest_notification.Letter_Type, 255)) AS [Letter Type],
	CONVERT
	(
		NVARCHAR(MAX),
		CASE
			WHEN latest_notification.Notification_ID IS NULL THEN 'N/A'
			WHEN latest_strike.Flag_Rehab = 1 OR (latest_strike.Flag_Is_Active = 0 AND NOT EXISTS
				 (SELECT 1 FROM HP_MAP_Canada._ref.MAP_Cutover_State AS retired
				  WHERE retired.Entity = 'STRIKE' AND retired.Source_Row_ID = latest_strike.ID
					AND retired.Cohort IN ('LEGACY_ONLY', 'EXCLUDE_EXPIRED_V2')))
				THEN CONCAT(latest_notification.Letter_Type, ' Rehabilitated')
			WHEN latest_notification.Communication_Sent_Date IS NULL
				THEN CONCAT(latest_notification.Letter_Type, ' To be Sent')
			WHEN latest_notification.Communication_Delivered_Date IS NULL
				THEN CONCAT(latest_notification.Letter_Type, ' Sent - Not Delivered')
			ELSE latest_notification.Letter_Type
		END
	) AS [MAP Status Detail],
	latest_notification.Communication_Delivered_Date AS [Letter Delivered Date],
	latest_notification.Generation_Date AS [Notification Generation Date],
	latest_strike.Buffer_Period_Start_Date AS [Buffer Period Start],
	latest_strike.Buffer_Period_End_Date AS [Buffer Period End],
	latest_strike.Product_Suspension_Start_Date AS [Product Suspension Start],
	latest_strike.Product_Suspension_End_Date AS [Product Suspension End],
	latest_strike.Penalty_Period_Start_Date AS [Penalty Period Start],
	latest_strike.Penalty_Period_End_Date_Adjusted AS [Penalty Period End],
	CONVERT(NVARCHAR(4000), LEFT(violation.Screenshot_URL, 4000)) AS Screenshot_URL,
	CONVERT(NUMERIC(38, 2), violation.DGF_Penalty) AS [DGF Penalty],
	CONVERT(NVARCHAR(200), LEFT(violation.Notes, 200)) AS Notes,
	CONVERT(NUMERIC(12, 2), violation.Tier_Pass_Through) AS Tier_Pass_Through,
	CONVERT
	(
		INT,
		CASE
			WHEN scaffold.[Location ID] = '99999999' THEN 1
			ELSE ISNULL(threshold_rule.Threshold_Action, threshold_fallback.Threshold_Action)
		END
	) AS [Category Threshold Highlight], -- Want to apply a threshold of 1 for HP
	CONVERT
	(
		INT,
		CASE
			WHEN scaffold.[Location ID] = '99999999' THEN 1
			ELSE ISNULL(threshold_rule.Threshold_Action, threshold_fallback.Threshold_Action)
		END
	) AS [Category Threshold Alert],
	contacts.HP_Rep1,
	contacts.HP_Rep2,
	contacts.HP_Rep3,
	contacts.HP_Rep4,
	contacts.HP_Rep5,
	contacts.HP_Rep6,
	contacts.Email1,
	contacts.Email2,
	contacts.Email3,
	contacts.Email4,
	contacts.Email5,
	contacts.Email6,
	CONVERT(INT, 0) AS [Matching Flag],
	CONVERT(INT, 0) AS [G20 Sel/Cat Flag],
	CAST(NULL AS NVARCHAR(255)) AS [Validation Status New],
	CAST(NULL AS INT) AS RunningTotal,
	ISNULL(upc.UPC, '') AS UPC,
	CONVERT(BIT, ISNULL(violation.Flag_Bundle, 0)) AS [Bundle Flag],
	min_violation.[Minimum Violation Date],
	listing_dates.[Minimum Listing Date],
	listing_dates.[Most Recent Listing Date],
	date_requested.[Date Requested],
	CONVERT(INT, CASE WHEN new_sku.SKU IS NOT NULL THEN 1 ELSE 0 END) AS [New SKU Flag],
	CONVERT(INT, CASE WHEN top_seller.New_Location_ID IS NULL THEN 0 ELSE 1 END) AS Top_Reseller_Flag,
	CAST(NULL AS DATE) AS [Latest Courtesy Alert Date],
	CONVERT(INT, ISNULL(violation.Login_Type_ID, 1)) AS Login_Type_ID,
	CONVERT
	(
		NVARCHAR(25),
		CASE WHEN ISNULL(violation.Flag_StrikeThrough, 0) = 1
			 THEN 'Strikethrough Pricing' ELSE 'Non-Strikethrough Pricing' END
	) AS [Strikethrough Flag],
	CONVERT
	(
		INT,
		CASE
			WHEN ISNULL(violation.Flag_Bundle, 0) = 0
			 AND EXISTS
			 (
				 SELECT 1
				 FROM #CA_Grace_Period AS gps
				 WHERE gps.Country = 'Canada'
				   AND gps.SKU = violation.SKU
				   AND scaffold.[Date] BETWEEN gps.Valid_From AND gps.Valid_To
			 ) THEN 1
			WHEN ISNULL(violation.Flag_Bundle, 0) = 1
			 AND EXISTS
			 (
				 SELECT 1
				 FROM #CA_Grace_Period AS gps_bundle
				 WHERE gps_bundle.Country = 'Canada'
				   AND violation.SKU LIKE '%' + gps_bundle.SKU + '%'
				   AND scaffold.[Date] BETWEEN gps_bundle.Valid_From AND gps_bundle.Valid_To
			 ) THEN 1
			ELSE 0
		END
	) AS [Price Increase SKU Flag],
	CONVERT(NVARCHAR(255), LEFT(content.Content_Source, 255)) AS [Content Provider],
	partner.Partner_ID,
	CONVERT(NVARCHAR(20), LEFT(ISNULL(violation.Violation_Type, 'N/A'), 20)) AS [Violation Type],
	CAST(NULL AS DATE) AS [Product Category Latest Courtesy Alert Date],
	warning_period.Penalty_Period_Start_Date AS [Monitoring Period Start],
	warning_period.Penalty_Period_End_Date_Adjusted AS [Monitoring Period End],
	consequence_period.Penalty_Period_Start_Date AS [Consequence Penalty Period Start],
	consequence_period.Penalty_Period_End_Date_Adjusted AS [Consequence Penalty Period End],
	CONVERT
	(
		INT,
		CASE
			WHEN violation.Flag_Triggered_Warning = 1 THEN 2
			WHEN warning_period.ID IS NOT NULL THEN 1
			ELSE 0
		END
	) AS Flag_Warning_Or_Monitoring
INTO #CA_OutputBase
FROM #CA_CTE_cj AS scaffold
LEFT JOIN #CA_ViolationRows AS violation
	ON violation.[Location ID] = scaffold.[Location ID]
   AND violation.Master_SID = scaffold.Master_SID --rv 4/12/23
   AND violation.[Product Subcategory] = scaffold.[Product Subcategory]
   AND violation.[Date] = scaffold.[Date]
LEFT JOIN #Fiscal_Week AS fiscal
	ON fiscal.Week_Begin_Date_Alt = scaffold.[Week]
LEFT JOIN #CA_TopResellers AS top_seller
	ON top_seller.New_Location_ID = scaffold.[Location ID]
OUTER APPLY
(
	SELECT TOP (1)
		ds.Supplies_Qualification,
		ds.Print_Qualification,
		ds.Qualified_Business_Personal_Systems,
		ds.Qualified_Consumer_Personal_Systems
	FROM HP_MAP_Canada._final.Dim_Seller AS ds
	WHERE ds.Master_SID = scaffold.Master_SID
	  AND scaffold.[Date] BETWEEN ds.Valid_From AND ds.Valid_To
	ORDER BY ds.Valid_From DESC, ds.Seller_ID DESC
) AS seller_at_date
LEFT JOIN #CA_ActiveQPP AS qpp
	ON qpp.HPI_Location_ID = scaffold.[Location ID]
LEFT JOIN #CA_LatestNotifications AS latest_notification
	ON latest_notification.New_Location_ID = scaffold.[Location ID]
   AND latest_notification.Product_Type = scaffold.[Product Subcategory Enforcement]
LEFT JOIN #CA_LatestStrikes AS latest_strike
	ON latest_strike.New_Location_ID = scaffold.[Location ID]
   AND latest_strike.Product_Type = scaffold.[Product Subcategory Enforcement]
-- Include past strikes when checking monitoring periods.
OUTER APPLY
(
	SELECT TOP (1)
		s.ID,
		s.Violation_Status,
		s.Penalty_Period_Start_Date,
		s.Penalty_Period_End_Date_Adjusted
	FROM #CA_ValidStrikes AS s
	WHERE s.New_Location_ID = scaffold.[Location ID]
	  AND s.Product_Type = scaffold.[Product Subcategory Enforcement]
	  AND LEFT(s.Violation_Status, 1) = 'W'
	  AND scaffold.[Date] BETWEEN s.Penalty_Period_Start_Date
							  AND s.Penalty_Period_End_Date_Adjusted
	ORDER BY s.Penalty_Period_Start_Date DESC, s.ID DESC
) AS warning_period
OUTER APPLY
(
	SELECT TOP (1)
		s.ID,
		s.Violation_Status,
		s.Penalty_Period_Start_Date,
		s.Penalty_Period_End_Date_Adjusted
	FROM #CA_ValidStrikes AS s
	WHERE s.New_Location_ID = scaffold.[Location ID]
	  AND s.Product_Type = scaffold.[Product Subcategory Enforcement]
	  AND LEFT(s.Violation_Status, 1) = 'C'
	  AND scaffold.[Date] BETWEEN s.Penalty_Period_Start_Date
							  AND s.Penalty_Period_End_Date_Adjusted
	ORDER BY s.Penalty_Period_Start_Date DESC, s.ID DESC
) AS consequence_period
OUTER APPLY
(
	SELECT
		CASE
			WHEN warning_period.ID IS NOT NULL THEN
				CASE warning_period.Violation_Status
					WHEN 'WF' THEN 'CF'
					WHEN 'W30' THEN 'C30'
					WHEN 'W60' THEN 'C60'
					WHEN 'W90' THEN 'C90'
					ELSE 'C30'
				END
			WHEN COALESCE(violation.[Seller Penalty Type], scaffold.[Seller Penalty Type]) LIKE '%Financial'
				THEN 'WF'
			WHEN consequence_period.Violation_Status = 'C30' THEN 'W60'
			WHEN consequence_period.Violation_Status IN ('C60', 'C90') THEN 'W90'
			ELSE 'W30'
		END AS Rule_Action
) AS threshold_action
OUTER APPLY
(
	SELECT TOP (1)
		r.Threshold_Action
	FROM [HP_MAP_Canada].[_ref].[Violation_Rules] AS r
	WHERE r.Program = 'MAP'
	  AND r.Seller_Group IN
		  (COALESCE(violation.[Reporting Group], scaffold.[Reporting Group], 'All'), 'All')
	  AND r.Penalty_Description = COALESCE(violation.[Seller Penalty Type], scaffold.[Seller Penalty Type])
	  AND r.Product_Type_Hybrid = scaffold.[Rule Product Type]
	  AND r.[Action] = threshold_action.Rule_Action
	  AND scaffold.[Date] BETWEEN r.Valid_From AND r.Valid_To
	ORDER BY
		CASE WHEN r.Seller_Group = COALESCE(violation.[Reporting Group], scaffold.[Reporting Group], 'All') THEN 0 ELSE 1 END,
		r.Valid_From DESC,
		r.ID DESC
) AS threshold_rule
OUTER APPLY
(
	SELECT
		CASE
			WHEN warning_period.ID IS NULL THEN 1
			WHEN scaffold.[Product Subcategory] IN ('Ink', 'Toner', 'C-SKU', 'G-SKU')
				THEN CASE WHEN COALESCE(violation.[Seller Penalty Type], scaffold.[Seller Penalty Type]) LIKE '%Financial%' THEN 10 ELSE 5 END
			ELSE 2
		END AS Threshold_Action
) AS threshold_fallback
LEFT JOIN #CA_CTE_Contacts AS contacts
	ON contacts.[New Location ID] = scaffold.[Location ID]  -- 9/10/20 LU added for G20 Contacts
   AND contacts.[Product Category] =
	   CASE
		   WHEN scaffold.[Product Subcategory] LIKE 'Large Format%' THEN 'Large Format'
		   WHEN scaffold.[Product Subcategory] IN ('C-SKU', 'G-SKU') THEN 'Supplies' --DP 1/12/23 adjusting join so Supplies contacts apply to C-SKU in tooltip
		   ELSE scaffold.[Product Category]
	   END
LEFT JOIN #CA_UPC_US AS upc
	ON upc.SKU = violation.SKU
LEFT JOIN #CA_MinViolationDate AS min_violation
	ON min_violation.New_Location_ID = scaffold.[Location ID]
LEFT JOIN #CA_Min_Max_Listing_Date AS listing_dates
	ON listing_dates.Master_New_Location_Id = scaffold.[Location ID]
LEFT JOIN #DateRequested AS date_requested
	ON date_requested.Master_New_Location_Id = scaffold.[Location ID]
   AND date_requested.Ctry = 'Canada'
LEFT JOIN #CA_NewSKU AS new_sku
	ON new_sku.SKU = violation.SKU
LEFT JOIN #CA_Content AS content
	ON content.HPI_Location_ID = scaffold.[Location ID]
   AND content.Country IN ('CA', 'Canada')
LEFT JOIN #CA_PartnerLookup AS partner
	ON partner.LocationId = scaffold.[Location ID]
WHERE scaffold.[Location ID] <> 'N/A' -- 10/14/24 ED

CREATE NONCLUSTERED INDEX IX_OutputBase_Selector
	ON #CA_OutputBase ([Location ID], [Date], SKU, Login_Type_ID)
	INCLUDE ([Week], [Product Subcategory], [Letter Type])

-- Rank report sellers using their distinct weekly SKUs.
DROP TABLE IF EXISTS #CA_WeeklySellerRanks
;WITH SellerWeeks AS
(
	SELECT
		output_base.Country,
		output_base.[Week],
		CONVERT(NVARCHAR(50), output_base.[Product Subcategory Enforcement]) AS [Product Subcategory Enforcement],
		output_base.Account,
		CONVERT(NVARCHAR(20), output_base.[Location ID]) AS [Location ID],
		MAX(output_base.Top_Reseller_Flag) AS Top_Reseller_Flag,
		COUNT(DISTINCT output_base.SKU) AS Violating_SKU_Count
	FROM #CA_OutputBase AS output_base
	GROUP BY
		output_base.Country,
		output_base.[Week],
		CONVERT(NVARCHAR(50), output_base.[Product Subcategory Enforcement]),
		output_base.Account,
		CONVERT(NVARCHAR(20), output_base.[Location ID])
)
SELECT
	Country,
	[Week],
	[Product Subcategory Enforcement],
	[Location ID],
	DENSE_RANK() OVER
	(
		PARTITION BY Country, [Week], [Product Subcategory Enforcement]
		ORDER BY Top_Reseller_Flag DESC, Violating_SKU_Count DESC, Account
	) AS Weekly_Seller_Rank
INTO #CA_WeeklySellerRanks
FROM SellerWeeks

CREATE UNIQUE CLUSTERED INDEX IX_WeeklySellerRanks_Week_Product_Location
	ON #CA_WeeklySellerRanks
	(Country, [Week], [Product Subcategory Enforcement], [Location ID])

DROP TABLE IF EXISTS #CA_FinalOutput
SELECT
	output_base.*,
	seller_rank.Weekly_Seller_Rank,
	ROW_NUMBER() OVER
	(
		PARTITION BY
			output_base.[Location ID],
			output_base.[Date],
			ISNULL(output_base.SKU, output_base.[Product Subcategory]),
			output_base.Login_Type_ID
		ORDER BY output_base.[Letter Type] DESC
	) AS Selector,
	ROW_NUMBER() OVER
	(
		PARTITION BY
			output_base.[Location ID],
			output_base.[Week],
			ISNULL(output_base.SKU, output_base.[Product Subcategory]),
			output_base.Login_Type_ID
		ORDER BY
			REPLACE(ISNULL(output_base.[Validation Status], 'Z'), 'Not Inspected', 'Z'),
			output_base.[Date]
	) AS [Weekly Violation Selector] -- 9/17/2020 LU: Moved up a line, certain weeks weren't getting a WVS of 1
INTO #CA_FinalOutput
FROM #CA_OutputBase AS output_base
INNER JOIN #CA_WeeklySellerRanks AS seller_rank
	ON seller_rank.Country = output_base.Country
   AND seller_rank.[Week] = output_base.[Week]
   AND seller_rank.[Product Subcategory Enforcement] = output_base.[Product Subcategory Enforcement]
   AND seller_rank.[Location ID] = output_base.[Location ID]


-- Prepare the report rows before updating the report table.
SELECT TOP (0) *
INTO #MAP_L12M_Ready
FROM [_report].[Violations_L12M]

DECLARE @ExpectedRows BIGINT

INSERT INTO #MAP_L12M_Ready
(
	[Country],
	[Validation Status],
	[Validation Status Weekly],
	[Fiscal Week Number],
	[Week],
	[Date],
	[Product Category],
	[Product Subcategory],
	[Product Subcategory Enforcement],
	[Fact ID],
	[SKU],
	[ASIN],
	[Product_Description],
	[Account],
	[Seller Name],
	[Storefront Name(s)],
	[Location ID],
	[Seller Status],
	[Termination Date],
	[Seller Penalty Type],
	[Reporting Group],
	[Market],
	[Log-in Type],
	[Price Location],
	[MAP],
	[Advertised Price],
	[Eligible IR],
	[Lowest Possible Price],
	[Validation_Status_Raw],
	[Letter Type],
	[MAP Status Detail],
	[Letter Delivered Date],
	[Notification Generation Date],
	[Buffer Period Start],
	[Buffer Period End],
	[Product Suspension Start],
	[Product Suspension End],
	[Penalty Period Start],
	[Penalty Period End],
	[Screenshot_URL],
	[DGF Penalty],
	[Notes],
	[Tier_Pass_Through],
	[Category Threshold Highlight],
	[Category Threshold Alert],
	[HP_Rep1],
	[HP_Rep2],
	[HP_Rep3],
	[HP_Rep4],
	[HP_Rep5],
	[HP_Rep6],
	[Email1],
	[Email2],
	[Email3],
	[Email4],
	[Email5],
	[Email6],
	[Selector],
	[Matching Flag],
	[G20 Sel/Cat Flag],
	[Weekly Violation Selector],
	[Validation Status New],
	[RunningTotal],
	[UPC],
	[Bundle Flag],
	[Minimum Violation Date],
	[Minimum Listing Date],
	[Most Recent Listing Date],
	[Date Requested],
	[New SKU Flag],
	[Top_Reseller_Flag],
	[Latest Courtesy Alert Date],
	[Login_Type_ID],
	[Strikethrough Flag],
	[Weekly_Seller_Rank],
	[Price Increase SKU Flag],
	[Content Provider],
	[Partner_ID],
	[Violation Type],
	[Product Category Latest Courtesy Alert Date],
	[Monitoring Period Start],
	[Monitoring Period End],
	[Consequence Penalty Period Start],
	[Consequence Penalty Period End],
	[Flag_Warning_Or_Monitoring]
)
SELECT
	final.Country,
	final.[Validation Status],
	final.[Validation Status Weekly],
	final.[Fiscal Week Number],
	final.[Week],
	final.[Date],
	final.[Product Category],
	final.[Product Subcategory],
	final.[Product Subcategory Enforcement],
	final.[Fact ID],
	final.SKU,
	final.ASIN,
	final.Product_Description,
	final.Account,
	final.[Seller Name],
	final.[Storefront Name(s)],
	final.[Location ID],
	final.[Seller Status],
	final.[Termination Date],
	final.[Seller Penalty Type],
	final.[Reporting Group],
	final.Market,
	final.[Log-in Type],
	final.[Price Location],
	final.MAP,
	final.[Advertised Price],
	final.[Eligible IR],
	final.[Lowest Possible Price],
	final.Validation_Status_Raw,
	final.[Letter Type],
	final.[MAP Status Detail],
	final.[Letter Delivered Date],
	final.[Notification Generation Date],
	final.[Buffer Period Start],
	final.[Buffer Period End],
	final.[Product Suspension Start],
	final.[Product Suspension End],
	final.[Penalty Period Start],
	final.[Penalty Period End],
	final.Screenshot_URL,
	final.[DGF Penalty],
	final.Notes,
	final.Tier_Pass_Through,
	final.[Category Threshold Highlight],
	final.[Category Threshold Alert],
	final.HP_Rep1,
	final.HP_Rep2,
	final.HP_Rep3,
	final.HP_Rep4,
	final.HP_Rep5,
	final.HP_Rep6,
	final.Email1,
	final.Email2,
	final.Email3,
	final.Email4,
	final.Email5,
	final.Email6,
	final.Selector,
	final.[Matching Flag],
	final.[G20 Sel/Cat Flag],
	final.[Weekly Violation Selector],
	final.[Validation Status New],
	final.RunningTotal,
	final.UPC,
	final.[Bundle Flag],
	final.[Minimum Violation Date],
	final.[Minimum Listing Date],
	final.[Most Recent Listing Date],
	final.[Date Requested],
	final.[New SKU Flag],
	final.Top_Reseller_Flag,
	final.[Latest Courtesy Alert Date],
	final.Login_Type_ID,
	final.[Strikethrough Flag],
	final.Weekly_Seller_Rank,
	final.[Price Increase SKU Flag],
	final.[Content Provider],
	final.Partner_ID,
	final.[Violation Type],
	final.[Product Category Latest Courtesy Alert Date],
	CASE WHEN final.[Date] >= CONVERT(DATE, '20261101') THEN final.[Monitoring Period Start] ELSE CONVERT(DATE, NULL) END,
	CASE WHEN final.[Date] >= CONVERT(DATE, '20261101') THEN final.[Monitoring Period End] ELSE CONVERT(DATE, NULL) END,
	CASE WHEN final.[Date] >= CONVERT(DATE, '20261101') THEN final.[Consequence Penalty Period Start] ELSE CONVERT(DATE, NULL) END,
	CASE WHEN final.[Date] >= CONVERT(DATE, '20261101') THEN final.[Consequence Penalty Period End] ELSE CONVERT(DATE, NULL) END,
	final.Flag_Warning_Or_Monitoring
FROM (SELECT * FROM #FinalOutput UNION ALL SELECT * FROM #CA_FinalOutput) AS final
WHERE final.[Date] BETWEEN @ExportStartDate AND @ThroughDate
SET @ExpectedRows = ROWCOUNT_BIG()

IF NOT EXISTS (SELECT 1 FROM #MAP_L12M_Ready WHERE Country = 'US')
	OR NOT EXISTS (SELECT 1 FROM #MAP_L12M_Ready WHERE Country = 'Canada')
BEGIN
	;THROW 51000, 'The L12M report needs rows for both the US and Canada.', 1
END

BEGIN TRY
	BEGIN TRANSACTION

	DELETE target
	FROM [_report].[Violations_L12M] AS target WITH (TABLOCKX)
	WHERE target.[Date] BETWEEN @ExportStartDate AND @ThroughDate
		AND target.Country IN ('US', 'Canada')

	INSERT INTO [_report].[Violations_L12M]
	(
		[Country], [Validation Status], [Validation Status Weekly], [Fiscal Week Number], [Week],
		[Date], [Product Category], [Product Subcategory], [Product Subcategory Enforcement],
		[Fact ID], [SKU], [ASIN], [Product_Description], [Account], [Seller Name],
		[Storefront Name(s)], [Location ID], [Seller Status], [Termination Date],
		[Seller Penalty Type], [Reporting Group], [Market], [Log-in Type], [Price Location], [MAP],
		[Advertised Price], [Eligible IR], [Lowest Possible Price], [Validation_Status_Raw],
		[Letter Type], [MAP Status Detail], [Letter Delivered Date], [Notification Generation Date],
		[Buffer Period Start], [Buffer Period End], [Product Suspension Start],
		[Product Suspension End], [Penalty Period Start], [Penalty Period End], [Screenshot_URL],
		[DGF Penalty], [Notes], [Tier_Pass_Through], [Category Threshold Highlight],
		[Category Threshold Alert], [HP_Rep1], [HP_Rep2], [HP_Rep3], [HP_Rep4], [HP_Rep5], [HP_Rep6],
		[Email1], [Email2], [Email3], [Email4], [Email5], [Email6], [Selector], [Matching Flag],
		[G20 Sel/Cat Flag], [Weekly Violation Selector], [Validation Status New], [RunningTotal],
		[UPC], [Bundle Flag], [Minimum Violation Date], [Minimum Listing Date],
		[Most Recent Listing Date], [Date Requested], [New SKU Flag], [Top_Reseller_Flag],
		[Latest Courtesy Alert Date], [Login_Type_ID], [Strikethrough Flag], [Weekly_Seller_Rank],
		[Price Increase SKU Flag], [Content Provider], [Partner_ID], [Violation Type],
		[Product Category Latest Courtesy Alert Date], [Monitoring Period Start],
		[Monitoring Period End], [Consequence Penalty Period Start], [Consequence Penalty Period End],
		[Flag_Warning_Or_Monitoring]
	)
	SELECT
		[Country], [Validation Status], [Validation Status Weekly], [Fiscal Week Number], [Week],
		[Date], [Product Category], [Product Subcategory], [Product Subcategory Enforcement],
		[Fact ID], [SKU], [ASIN], [Product_Description], [Account], [Seller Name],
		[Storefront Name(s)], [Location ID], [Seller Status], [Termination Date],
		[Seller Penalty Type], [Reporting Group], [Market], [Log-in Type], [Price Location], [MAP],
		[Advertised Price], [Eligible IR], [Lowest Possible Price], [Validation_Status_Raw],
		[Letter Type], [MAP Status Detail], [Letter Delivered Date], [Notification Generation Date],
		[Buffer Period Start], [Buffer Period End], [Product Suspension Start],
		[Product Suspension End], [Penalty Period Start], [Penalty Period End], [Screenshot_URL],
		[DGF Penalty], [Notes], [Tier_Pass_Through], [Category Threshold Highlight],
		[Category Threshold Alert], [HP_Rep1], [HP_Rep2], [HP_Rep3], [HP_Rep4], [HP_Rep5], [HP_Rep6],
		[Email1], [Email2], [Email3], [Email4], [Email5], [Email6], [Selector], [Matching Flag],
		[G20 Sel/Cat Flag], [Weekly Violation Selector], [Validation Status New], [RunningTotal],
		[UPC], [Bundle Flag], [Minimum Violation Date], [Minimum Listing Date],
		[Most Recent Listing Date], [Date Requested], [New SKU Flag], [Top_Reseller_Flag],
		[Latest Courtesy Alert Date], [Login_Type_ID], [Strikethrough Flag], [Weekly_Seller_Rank],
		[Price Increase SKU Flag], [Content Provider], [Partner_ID], [Violation Type],
		[Product Category Latest Courtesy Alert Date], [Monitoring Period Start],
		[Monitoring Period End], [Consequence Penalty Period Start], [Consequence Penalty Period End],
		[Flag_Warning_Or_Monitoring]
	FROM #MAP_L12M_Ready

	IF ROWCOUNT_BIG() <> @ExpectedRows
	BEGIN
		;THROW 51000, 'The number of rows inserted differs from the prepared report.', 1
	END

	COMMIT TRANSACTION
END TRY
BEGIN CATCH
	IF XACT_STATE() <> 0
		ROLLBACK TRANSACTION
	;THROW
END CATCH

-- Send the email after the report is committed.
BEGIN TRY
	IF HP_MAP_Prod.dbo.CanSendDbMail() = 1
	BEGIN
		DECLARE @MailReturn INT
		EXEC @MailReturn = msdb.dbo.sp_send_dbmail
			@profile_name = 'QDN Support',
			@recipients = 'pbelezhkov@dsmengines.com;edeneva@dsmengines.com;zfraile@dsmengines.com',
			@body = 'The _report.Violations_L12M table has been refreshed.',
			@subject = 'The Violations L12M export has been generated',
			@body_format = 'HTML'

		IF ISNULL(@MailReturn, -1) <> 0
		BEGIN
			;THROW 51000, 'Database Mail did not queue the report email.', 1
		END
	END
END TRY
BEGIN CATCH
	DECLARE @MailError NVARCHAR(2048) = ERROR_MESSAGE()
	RAISERROR('The L12M report was refreshed, but the email failed. %s', 10, 1, @MailError) WITH NOWAIT
END CATCH
END
GO
