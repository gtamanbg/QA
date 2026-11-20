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
CREATE PROCEDURE [_old].[SP_VIOLATIONS_L12M]
@P_Export_Start_Date DATE = NULL,
@P_Generate_Full_Refresh BIT = 0
AS
BEGIN
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

DROP TABLE IF EXISTS #Product_Category
CREATE TABLE #Product_Category (
	[Product_Category] [nvarchar](255) NULL,
	[Product_Subcategory] [nvarchar](255) NULL
) ON [PRIMARY]

INSERT INTO #Product_Category (Product_Category, Product_Subcategory)
VALUES 
	('Supplies', 'Ink'),
	('Supplies', 'Toner'),
	('Supplies', 'C-SKU'),
	('Supplies', 'G-SKU'),
	('Print', 'Inkjet'),
	('Print', 'LaserJet'),
	('Large Format', 'Large Format'),
	('Large Format', 'Large Format Supplies'),
	('PS', 'BPS Display'),
	('PS', 'CPS Desktop'),
	('PS', 'CPS Display'),
	('PS', 'CPS Notebook'),
	('Print', 'Scanjet');	-- Scanjet Inclusion

--Start date
DECLARE @startDate date = (SELECT d.Week_Begin_Date_Alt FROM _final.Dim_Date d WITH (NOLOCK) WHERE d.Full_Date = DATETRUNC(MONTH,DATEADD(MONTH,-12,GETDATE())))
DECLARE @maxFileDateUPC_US date = (SELECT MAX([File Date]) FROM _analysis.MAP_Price_List_Tool_Export_NEW WITH(NOLOCK))
DECLARE @maxFileDateUPC_CAN date = (SELECT MAX([File Date]) FROM HP_MAP_Canada._analysis.MAP_Price_List_Tool_Export_NEW WITH(NOLOCK))

DROP TABLE IF EXISTS #Weeks
SELECT DISTINCT Week_Begin_Date_Alt [Week], Full_Date [Date]
INTO #Weeks
FROM _final.Dim_Date dt WITH(NOLOCK)  -- 9/10/20 LU adjusted to Dim_Date to include days even if no data loaded. 
WHERE dt.Week_Begin_Date_Alt >= @startDate
	AND Full_Date < CAST(GETDATE() AS DATE)

DROP TABLE IF EXISTS #UPC_US
SELECT SKU, 
       ISNULL(UPC,'') UPC
INTO #UPC_US
FROM _analysis.MAP_Price_List_Tool_Export_NEW WITH(NOLOCK)
WHERE [File Date] = @maxFileDateUPC_US

DROP TABLE IF EXISTS #UPC_CAN
SELECT SKU, 
       ISNULL(UPC,'') UPC
INTO #UPC_CAN
FROM HP_MAP_Canada._analysis.MAP_Price_List_Tool_Export_NEW WITH(NOLOCK)
WHERE [File Date] = @maxFileDateUPC_CAN

DROP TABLE IF EXISTS #ViolationsPre
SELECT
	Violation_ID, Listing_ID, Week_Start_Date, Seller_Name, Seller_Name_HP, Seller_Name_Unified, New_Location_ID, [Option], Seller_Status, SKU, Price_Location,
	CASE
		WHEN Product_Line = '4X' THEN 'Scanjet'
		ELSE Product_Type
	END AS Product_Type,	-- Scanjet Inclusion
	Product_Line, Product_Condition, Market, Market_Unified, MAP, Seller_Regular_Price, Seller_Advertised_Price, Seller_Savings, Collected_Date, Product_Page, Screenshot_URL, Violation_Code, Violation_Description, Eligible_National_Promo, 
	Eligible_IR_Amount, Lowest_Possible_Price, DSM_Report_Date, Flag_Penalty_Violation, Data_Source, Flag_Sent_To_ACB, Validation_Status, Validation_Date, Approval_Status, Notification_ID, Group_Violation_ID, Fact_ID, Reason_ID, 
	CASE
		WHEN Product_Line = '4X' THEN 'Scanjet'
		ELSE Product_Type_Reporting
	END AS Product_Type_Reporting,	-- Scanjet Inclusion
	Rollup_ID, Flag_Master_Violation_ID, Threshold_ID, Flag_Sent_For_VI, Violation_Rule_ID, Fact_Version_Number, Insert_Date, Version_Number, Flag_Sample_Proof, Seller_Type, HPS_Promo_Option, OPS_Promo_Option, Master_SID,
	Seller_Reporting_Group, Seller_Penalty_Type, Validated_By, PC_Up,
	CASE
		WHEN Product_Line = '4X' THEN 'Scanjet'
		ELSE Product_Type_Enforcement
	END AS Product_Type_Enforcement,	-- Scanjet Inclusion
	Comments, HP_Reason_ID, Pass_Through_Code, Tier_Pass_Through,
	CASE
		WHEN Product_Line = '4X' THEN 'Scanjet'
		ELSE Product_Type_Threshold
	END AS Product_Type_Threshold,	-- Scanjet Inclusion
	Flag_Bundle, Courtesy_Alerts_Notification_ID, Login_Type_ID,
	CASE
		WHEN a.Violation_Code = 6 THEN 'C-SKU - Restricted'
		WHEN a.Violation_Code = 8 THEN 'Strike-through'
		WHEN a.Violation_Code = 9 THEN 'Price - Coupon'
		WHEN a.Flag_Bundle = 1 THEN 'Price - Bundle'
		WHEN a.Price_Location = 'Product Page Ad' THEN 'Price - Product Page'
		WHEN a.Price_Location = 'Shopping Cart' THEN 'Price - In-Cart'
		ELSE 'Electronic Content'
	END AS Violation_Type
INTO #ViolationsPre
FROM _old.ViolationsMAP a WITH(NOLOCK)
WHERE a.Collected_Date >= @startDate

DROP TABLE IF EXISTS #DailyViolationsPre
SELECT a.*
INTO #DailyViolationsPre
FROM _analysis.Daily_MAP_Violations_VI a WITH(NOLOCK)
WHERE a.Collected_Date >= @startDate

DROP TABLE IF EXISTS #ViolationsPre_CA
SELECT
	Violation_ID, Listing_ID, Week_Start_Date, Seller_Name, Seller_Name_HP, Seller_Name_Unified, New_Location_ID, [Option], Seller_Status, SKU, Price_Location,
	CASE
		WHEN Product_Line = '4X' THEN 'Scanjet'
		ELSE Product_Type
	END AS Product_Type,	-- Scanjet Inclusion
	Product_Line, Product_Condition, Market, Market_Unified, MAP, Seller_Regular_Price,
	Seller_Advertised_Price, Seller_Savings, Collected_Date, Product_Page, Screenshot_URL, Violation_Code, Violation_Description, Eligible_National_Promo, Eligible_IR_Amount, Lowest_Possible_Price, DSM_Report_Date, Flag_Penalty_Violation,
	Data_Source, Flag_Sent_To_ACB, Validation_Status, Validation_Date, Approval_Status, Notification_ID, Group_Violation_ID, Fact_ID, Reason_ID,
	CASE
		WHEN Product_Line = '4X' THEN 'Scanjet'
		ELSE Product_Type_Reporting
	END AS Product_Type_Reporting,	-- Scanjet Inclusion
	Rollup_ID, Flag_Master_Violation_ID, Threshold_ID, Flag_Sent_For_VI,
	Violation_Rule_ID, Fact_Version_Number, Insert_Date, Version_Number, Flag_Sample_Proof, Seller_Type, HPS_Promo_Option, OPS_Promo_Option, Master_SID, Seller_Reporting_Group, Seller_Penalty_Type, Validated_By, PC_Up,
	CASE
		WHEN Product_Line = '4X' THEN 'Scanjet'
		ELSE Product_Type_Enforcement
	END AS Product_Type_Enforcement,	-- Scanjet Inclusion
	Comments, HP_Reason_ID, Pass_Through_Code, Tier_Pass_Through,
	CASE
		WHEN Product_Line = '4X' THEN 'Scanjet'
		ELSE Product_Type_Threshold
	END AS Product_Type_Threshold,	-- Scanjet Inclusion
	Flag_Bundle, Courtesy_Alerts_Notification_ID, Login_Type_ID,
	CASE
		WHEN a.Violation_Code = 6 THEN 'C-SKU - Restricted'
		WHEN a.Violation_Code = 8 THEN 'Strike-through'
		WHEN a.Violation_Code = 9 THEN 'Price - Coupon'
		WHEN a.Flag_Bundle = 1 THEN 'Price - Bundle'
		WHEN a.Price_Location = 'Product Page Ad' THEN 'Price - Product Page'
		WHEN a.Price_Location = 'Shopping Cart' THEN 'Price - In-Cart'
		ELSE 'Electronic Content'
	END AS Violation_Type
INTO #ViolationsPre_CA
FROM HP_MAP_Canada._old.ViolationsMAP a WITH(NOLOCK)
WHERE a.Collected_Date >= @startDate

DROP TABLE IF EXISTS #DailyViolationsPre_CA
SELECT a.*
INTO #DailyViolationsPre_CA
FROM HP_MAP_Canada._analysis.Daily_MAP_Violations_VI a WITH(NOLOCK)
WHERE a.Collected_Date >= @startDate

DROP TABLE IF EXISTS #MinViolationDate
SELECT New_Location_ID, MIN(Collected_Date) [Minimum Violation Date]
INTO #MinViolationDate
FROM _old.ViolationsMAP WITH(NOLOCK)
WHERE Collected_Date >= '2023-11-01'
GROUP BY New_Location_ID

DROP TABLE IF EXISTS #MinViolationDate_CA
SELECT New_Location_ID
	  ,MIN(Collected_Date) [Minimum Violation Date]
INTO #MinViolationDate_CA
FROM HP_MAP_Canada._old.ViolationsMAP WITH(NOLOCK)
WHERE Collected_Date >= '2023-11-01'
GROUP BY New_Location_ID

DROP TABLE IF EXISTS #Min_Max_Listing_Date
SELECT s.Master_New_Location_Id
	  ,MIN(CAST(f.Collected_Date AS DATE)) [Minimum Listing Date]
	  ,MAX(CAST(f.Collected_Date AS DATE)) [Most Recent Listing Date]
INTO #Min_Max_Listing_Date
FROM _final.Fact_Listings f WITH(NOLOCK)
JOIN _final.Dim_Seller s WITH(NOLOCK) ON s.Seller_ID = f.Seller_ID
WHERE CAST(f.Collected_Date AS DATE) >= '2023-11-01'
      AND s.Master_New_Location_Id <> 'N/A'
GROUP BY s.Master_New_Location_ID

DROP TABLE IF EXISTS #Min_Max_Listing_Date_CA
SELECT s.Master_New_Location_Id
	  ,MIN(CAST(f.Collected_Date AS DATE)) [Minimum Listing Date]
	  ,MAX(CAST(f.Collected_Date AS DATE)) [Most Recent Listing Date]
INTO #Min_Max_Listing_Date_CA
FROM HP_MAP_Canada._final.Fact_Listings f WITH(NOLOCK)
JOIN HP_MAP_Canada._final.Dim_Seller s WITH(NOLOCK) ON s.Seller_ID = f.Seller_ID
WHERE CAST(f.Collected_Date AS DATE) >= '2023-11-01'
      AND s.Master_New_Location_Id <> 'N/A'
GROUP BY s.Master_New_Location_ID

DROP TABLE IF EXISTS #DateRequested
SELECT Country [Ctry]
      ,Master_New_Location_Id
      ,Account [Account Name]
	  ,Date_Requested [Date Requested]
INTO #DateRequested
FROM _analysis.PM_Monitoring_List WITH (NOLOCK)

DROP TABLE IF EXISTS #NewSKU
SELECT DISTINCT SKU
INTO #NewSKU
FROM _ref.SKU_Enforcement_Exclusion WITH (NOLOCK)
WHERE Flag_Reporting = 1

DROP TABLE IF EXISTS #NewSKU_CA
SELECT DISTINCT SKU
INTO #NewSKU_CA
FROM [HP_MAP_Canada]._ref.SKU_Enforcement_Exclusion WITH (NOLOCK)
WHERE Flag_Reporting = 1

DROP TABLE IF EXISTS #CourtesyAlerts
SELECT New_Location_ID, Product_Type, Alerts_Product_Type, MAX(Communication_Delivered_Date) MAX_Delivered_Date
INTO #CourtesyAlerts
FROM _ref.Courtesy_Alerts WITH (NOLOCK)
WHERE Notification_Approval_Status = 1
    AND Retracted_Alert_Flag = 0
GROUP BY New_Location_ID
		,Product_Type
		,Alerts_Product_Type

DROP TABLE IF EXISTS #CourtesyAlerts_CA
SELECT New_Location_ID, Product_Type, Alerts_Product_Type, MAX(Communication_Delivered_Date) MAX_Delivered_Date
INTO #CourtesyAlerts_CA
FROM [HP_MAP_Canada]._ref.Courtesy_Alerts WITH (NOLOCK)
WHERE Notification_Approval_Status = 1
    AND Retracted_Alert_Flag = 0
GROUP BY New_Location_ID
		,Product_Type
		,Alerts_Product_Type

DROP TABLE IF EXISTS #CourtesyAlertsProductCategory
SELECT c.New_Location_ID, pr.Product_Category_Reporting, MAX(Communication_Delivered_Date) MAX_Delivered_Date_Product_Category
INTO #CourtesyAlertsProductCategory
FROM _ref.Courtesy_Alerts c WITH (NOLOCK)
LEFT JOIN _final.Dim_Product pr WITH (NOLOCK)
ON c.Alerts_Product_Type = pr.Product_Type_Indirect_MAP
AND pr.Flag_Current = 1
WHERE c.Notification_Approval_Status = 1
    AND c.Retracted_Alert_Flag = 0
	AND pr.Product_Category_Reporting <> 'N/A'
GROUP BY c.New_Location_ID
		,pr.Product_Category_Reporting

DROP TABLE IF EXISTS #CourtesyAlertsProductCategory_CA
SELECT c.New_Location_ID, pr.Product_Category_Reporting, MAX(Communication_Delivered_Date) MAX_Delivered_Date_Product_Category
INTO #CourtesyAlertsProductCategory_CA
FROM HP_MAP_Canada._ref.Courtesy_Alerts c WITH (NOLOCK)
LEFT JOIN _final.Dim_Product pr WITH (NOLOCK)
ON c.Alerts_Product_Type = pr.Product_Type_Indirect_MAP
AND pr.Flag_Current = 1
WHERE c.Notification_Approval_Status = 1
    AND c.Retracted_Alert_Flag = 0
	AND pr.Product_Category_Reporting <> 'N/A'
GROUP BY c.New_Location_ID
		,pr.Product_Category_Reporting

DROP TABLE IF EXISTS #Grace_Period
SELECT *
INTO #Grace_Period
FROM (SELECT DISTINCT 'US' [Country], SKU, Valid_From, Valid_To
	  FROM _ref.Grace_Period_SKUs WITH (NOLOCK)
	  UNION
      SELECT DISTINCT 'Canada' [Country], SKU, Valid_From, Valid_To
	  FROM [HP_MAP_Canada]._ref.Grace_Period_SKUs WITH (NOLOCK)
      ) a

DROP TABLE IF EXISTS #Content
SELECT Country
       ,HPI_Location_ID
	   ,Content_Source
INTO #Content
FROM (SELECT Country
       ,b.HPI_Location_ID
       ,b.Content_Provider [Content_Source]
       ,RN = ROW_NUMBER() OVER(PARTITION BY HPI_Location_ID ORDER BY [Create_Date] DESC)
	FROM HP_QPP_Prod._WEB.tbl_assessment_form_bg B WITH (NOLOCK)
	WHERE b.Flag_Active = 1
			AND b.Flag_Current = 1
	 ) a
WHERE RN = 1

DROP TABLE IF EXISTS #Violations
SELECT 
	  a.*
	, dp.Product_Category_Reporting
	, sel.Supplies_Qualification
	, sel.Print_Qualification
	, sel.Qualified_Business_Personal_Systems
	, sel.Qualified_Consumer_Personal_Systems
	, dbo.FN_GET_SELLER_STATUS (dp.Product_Category_Reporting, sel.Supplies_Qualification, sel.Print_Qualification,sel.Qualified_Business_Personal_Systems, sel.Qualified_Consumer_Personal_Systems) as Seller_Status_Calc
	, nm.DGF_Penalty
INTO #Violations
FROM #ViolationsPre a
JOIN _final.Dim_Product dp WITH(NOLOCK) 
	ON	a.SKU = dp.SKU
	AND a.Collected_Date BETWEEN dp.Valid_From and dp.Valid_To
	--AND dp.In_MAP_Scope_Flag = 'In MAP Scope'
	AND (dp.In_MAP_Scope_Flag = 'In MAP Scope' OR dp.Product_Line = '4X')	-- Scanjet Inclusion
JOIN _final.Dim_Seller sel WITH(NOLOCK) 
	ON	a.New_Location_ID = sel.Master_New_Location_Id
	AND a.Collected_Date BETWEEN sel.Valid_From and sel.Valid_To
LEFT JOIN HP_QPP_Prod._web.tbl_partner p WITH(NOLOCK)
	ON	a.New_Location_ID = p.HPI_Location_ID
	AND	p.Flag_Active = 1
	AND p.Flag_Current = 1
	AND p.[Status] = 'Active'
	AND p.Country = 'US'
LEFT JOIN _ref.Notifications_MAP nm WITH(NOLOCK)
	ON ISNULL(a.Notification_ID,-999) = nm.Notification_ID
WHERE 
	p.HPI_Location_ID IS NOT NULL 
	OR sel.Master_New_Location_Id = '99999999'

CREATE NONCLUSTERED INDEX IX_Violations_New_Location_ID_SKU_Date ON #Violations(New_Location_ID, SKU, Collected_Date);

DROP TABLE IF EXISTS #Violations_CA
SELECT 
	a.*
	, dp.Product_Category_Reporting
	, dp.Product_Description
	, dp.CSKU_Flag
	, dp.Government_SKU_Flag
	, dp.Product_Type_Indirect_MAP [Product_Type_Indirect_MAP_Dim_Product]
	, sel.Supplies_Qualification
	, sel.Print_Qualification
	, sel.Qualified_Business_Personal_Systems
	, sel.Qualified_Consumer_Personal_Systems
	, dbo.FN_GET_SELLER_STATUS (dp.Product_Category_Reporting, sel.Supplies_Qualification, sel.Print_Qualification,sel.Qualified_Business_Personal_Systems, sel.Qualified_Consumer_Personal_Systems) as Seller_Status_Calc
	, nm.DGF_Penalty
INTO #Violations_CA
FROM #ViolationsPre_CA a
JOIN HP_MAP_Canada._final.Dim_Product dp WITH(NOLOCK) 
	ON	a.SKU = dp.SKU
	AND a.Collected_Date between dp.Valid_From and dp.Valid_To
	--AND dp.In_MAP_Scope_Flag = 'In MAP Scope'
	AND (dp.In_MAP_Scope_Flag = 'In MAP Scope' OR dp.Product_Line = '4X')	-- Scanjet Inclusion
JOIN HP_MAP_Canada._final.Dim_Seller sel WITH(NOLOCK) 
	ON	a.New_Location_ID = sel.Master_New_Location_Id
	AND a.Collected_Date between sel.Valid_From and sel.Valid_To
-- 	AND sel.Flag_Current = 1
LEFT JOIN HP_QPP_Prod._web.tbl_partner p WITH(NOLOCK)
	ON	a.New_Location_ID = p.HPI_Location_ID
	AND	p.Flag_Active = 1
	AND p.Flag_Current = 1
	AND p.[Status] = 'Active'
	AND p.Country IN ('CA', 'Canada')
LEFT JOIN HP_MAP_Canada._ref.Notifications_MAP nm WITH(NOLOCK)
	ON ISNULL(a.Notification_ID,-999) = nm.Notification_ID
WHERE 
	p.HPI_Location_ID IS NOT NULL 
	OR sel.Master_New_Location_Id = '99999999'

CREATE NONCLUSTERED INDEX IX_Violations_CA_New_Location_ID_SKU_Date ON #Violations_CA(New_Location_ID, SKU, Collected_Date);

DROP TABLE IF EXISTS #DailyViolations 
SELECT a.*
	, dp.Product_Category_Reporting
	, sel.Master_SID
	, sel.Supplies_Qualification
	, sel.Print_Qualification
	, sel.Qualified_Business_Personal_Systems
	, sel.Qualified_Consumer_Personal_Systems
	, dbo.FN_GET_SELLER_STATUS (dp.Product_Category_Reporting, sel.Supplies_Qualification, sel.Print_Qualification,sel.Qualified_Business_Personal_Systems, sel.Qualified_Consumer_Personal_Systems) as Seller_Status_Calc
INTO #DailyViolations
FROM #DailyViolationsPre a
JOIN _final.Dim_Product dp WITH(NOLOCK) 
	ON	a.SKU = dp.SKU
	AND cast(a.Collected_Date as date) between dp.Valid_From and dp.Valid_To
JOIN _final.Dim_Seller sel WITH(NOLOCK) 
	ON	a.Master_New_Location_Id = sel.Master_New_Location_Id
	AND cast (a.Collected_Date AS DATE) between sel.Valid_From and sel.Valid_To
	--AND sel.Flag_Current = 1
LEFT JOIN HP_QPP_Prod._web.tbl_partner p WITH(NOLOCK)
	ON	a.Master_New_Location_Id = p.HPI_Location_ID
	AND	p.Flag_Active = 1
	AND p.Flag_Current = 1
	AND p.[Status] = 'Active'
	AND p.Country = 'US'
WHERE 
	p.HPI_Location_ID IS NOT NULL 
	OR sel.Master_New_Location_Id = '99999999'

CREATE NONCLUSTERED INDEX IX_DailyViolations_Master_New_Location_Id_SKU_Date ON #DailyViolations(Master_New_Location_Id, SKU, Collected_Date);

DROP TABLE IF EXISTS #DailyViolations_CA
SELECT a.*
	,dt.Week_Begin_Date_Alt AS [Week]
	,dp.Product_Category_Reporting
	,dp.Product_Category_Reporting [Product Category]
	,CASE 
		WHEN dp.CSKU_Flag = 'C-SKU' THEN 'C-SKU'
		WHEN (dp.Government_SKU_Flag = 'Government SKU' AND dp.Product_Category_Reporting = 'Supplies') THEN 'G-SKU'
		WHEN dp.Product_Line = '4X' THEN 'Scanjet'	-- Scanjet Inclusion
		ELSE dp.Product_Type_Indirect_MAP 
		END [Product Subcategory]
	,CASE 
		WHEN dp.Product_Type_Indirect_MAP IN ('Ink','Toner') THEN 'Ink & Toner'
		WHEN dp.Product_Type_Indirect_MAP LIKE 'Large Format%' THEN 'Large Format'
		WHEN dp.Product_Line = '4X' THEN 'Scanjet'	-- Scanjet Inclusion
		ELSE dp.Product_Type_Indirect_MAP 
		END [Product Subcategory Enforcement]
	,CASE WHEN a.Market IN ('Websites Canada','Jet') 
					OR (a.Market = 'Amazon Canada' AND a.Master_New_Location_Id = '10241372')
					OR (a.Market = 'Newegg Canada' AND a.Master_New_Location_Id = '10248471')
					OR (a.Market = 'Walmart Canada' AND a.Master_New_Location_Id = '10292113')
					THEN 1 
				WHEN a.Market = 'Amazon Canada' THEN 2
				WHEN a.Market = 'Walmart Canada' THEN 3
				WHEN a.Market = 'Ebay Canada' THEN 4
				WHEN a.Market = 'Newegg Canada' THEN 5 
				WHEN a.Market = 'Best Buy Canada' THEN 6 
				ELSE 7 END Market_Unified_ID
	,sel.Master_SID
	,sel.Seller_Name_Unified [Account]
	,sel.Supplies_Qualification
	,sel.Print_Qualification
	,sel.Qualified_Business_Personal_Systems
	,sel.Qualified_Consumer_Personal_Systems
	,dbo.FN_GET_SELLER_STATUS (dp.Product_Category_Reporting, sel.Supplies_Qualification, sel.Print_Qualification,sel.Qualified_Business_Personal_Systems, sel.Qualified_Consumer_Personal_Systems) as Seller_Status_Calc
INTO #DailyViolations_CA
FROM #DailyViolationsPre_CA a
JOIN HP_MAP_Canada._final.Dim_Product dp WITH(NOLOCK) 
	ON	a.SKU = dp.SKU
	AND cast(a.Collected_Date as date) between dp.Valid_From and dp.Valid_To
JOIN HP_MAP_Canada._final.Dim_Seller sel WITH(NOLOCK) 
	ON	a.Master_New_Location_Id = sel.Master_New_Location_Id
	AND cast (a.Collected_Date AS DATE) between sel.Valid_From and sel.Valid_To
	--AND sel.Flag_Current = 1
LEFT JOIN HP_QPP_Prod._web.tbl_partner p WITH(NOLOCK)
	ON	a.Master_New_Location_Id = p.HPI_Location_ID
	AND	p.Flag_Active = 1
	AND p.Flag_Current = 1
	AND p.[Status] = 'Active'
	AND p.Country IN ('CA', 'Canada')
JOIN HP_MAP_Canada._final.Dim_Date dt WITH(NOLOCK) 
	ON	a.Collected_Date = dt.Full_Date
WHERE p.HPI_Location_ID IS NOT NULL 
      OR sel.Master_New_Location_Id = '99999999'

CREATE NONCLUSTERED INDEX IX_DailyViolations_CA_Master_New_Location_Id_SKU_Date ON #DailyViolations_CA(Master_New_Location_Id, SKU, Collected_Date);

DROP TABLE IF EXISTS #ListingIDs
SELECT DISTINCT Fact_ID
INTO #ListingIDs
FROM (
	SELECT DISTINCT Fact_ID FROM #Violations
	UNION
	SELECT DISTINCT Fact_ID FROM #DailyViolations
) a

CREATE CLUSTERED INDEX IX_ListingIDs_Fact_ID ON #ListingIDs(Fact_ID);

DROP TABLE IF EXISTS #ListingIDs_CA
SELECT DISTINCT Fact_ID
INTO #ListingIDs_CA
FROM (
	SELECT DISTINCT Fact_ID FROM #Violations_CA
	UNION
	SELECT DISTINCT Fact_ID FROM #DailyViolations_CA
) a

CREATE CLUSTERED INDEX IX_ListingIDs_CA_Fact_ID ON #ListingIDs_CA(Fact_ID);

DROP TABLE IF EXISTS #Listings
SELECT a.*
	, ss.Screenshot_URL
INTO #Listings
FROM (
	SELECT fact.*,
		CASE 
			WHEN fact.Data_Source_ID < 4 OR fact.Data_Source_ID = 10 THEN fact.NewMo_Screenshot_ID 
			WHEN fact.Data_Source_ID = 4 THEN fact.ACB_Screenshot_ID
			WHEN fact.Data_Source_ID = 5 THEN fact.NewMo_Intraday_Screenshot_ID  -- 4/5/2020 LU: Added NewMo_Intraday_Screenshot_ID > 3 for 4/5 Intraday Enforcement launch 
			WHEN fact.Data_Source_ID = 7 THEN fact.Syndigo_Screenshot_ID  -- 7/6/2020 RV: Added Syndigo_Screenshot_ID 
			WHEN fact.Data_Source_ID = 8 THEN fact.Corsearch_Screenshot_ID -- 9/16/23 ED: Added Corsearch Screneshot_ID
			END as Screenshot_ID
	FROM _final.Fact_Listings fact WITH(NOLOCK)
	JOIN #ListingIDs v on fact.Id = v.Fact_ID
) a
JOIN _final.Dim_Screenshot ss  WITH(NOLOCK) ON a.Screenshot_ID = ss.Screenshot_ID

DROP TABLE IF EXISTS #Listings_CA
SELECT a.*
	, ss.Screenshot_URL
INTO #Listings_CA
FROM (
	SELECT fact.*,
		CASE WHEN fact.Data_Source_ID = 9 THEN fact.Corsearch_Screenshot_ID -- 9/16/23 ED: Added Corsearch Screneshot_ID
			ELSE fact.NewMo_Screenshot_ID 
			END AS Screenshot_ID
	FROM HP_MAP_Canada._final.Fact_Listings fact WITH(NOLOCK)
	JOIN #ListingIDs_CA v ON fact.Id = v.Fact_ID
) a
JOIN HP_MAP_Canada._final.Dim_Screenshot ss  WITH(NOLOCK) ON a.Screenshot_ID = ss.Screenshot_ID

DROP TABLE IF EXISTS #StoreFrontNames
SELECT Country
	,New_Location_ID
	,STRING_AGG(Storefront_Names, '; ') WITHIN GROUP (ORDER BY mpa_date ASC) AS StoreFrontName
INTO #StoreFrontNames
FROM (
	SELECT DISTINCT Country
		,New_Location_ID
		,Storefront_Names
		,MPA_Date 
	FROM _ref.Marketplace_Approved WITH(NOLOCK) 
	WHERE Flag_Active = 1 
	AND Flag_Current = 1 
	--AND Country = 'US'
) a
GROUP BY Country, New_Location_ID

-- Fiscal Week Calculation
DROP TABLE IF EXISTS #Fiscal_Week
SELECT DISTINCT 
	Week_Begin_Date_Alt
    ,Fiscal_Week_Number
INTO #Fiscal_Week
FROM (
	SELECT DISTINCT 
		[Year]
		,Fiscal_Year
		,Yearmo
		,Fiscal_Month
		,Week_Begin_Date_Alt 
		,DENSE_RANK () OVER (PARTITION BY Fiscal_Year ORDER BY Week_Begin_Date_Alt) [Fiscal_Week_Number]
	FROM _final.Dim_Date WITH(NOLOCK)
) a 
WHERE 
	Fiscal_Week_Number <53
AND Week_Begin_Date_Alt > = '2015-11-01'
ORDER BY Week_Begin_Date_Alt

--PENDING: Remove Fact ID and pull screenshot URL above at time of Daily creation
DROP TABLE IF EXISTS #CTE_Adhoc --Adhoc visual inspections conducted Mondays: Prioritized due to inspecting all violations
SELECT a.Fact_ID [Fact ID]
	,fact.Data_Source_ID
	,Week_Begin_Date_Alt [Week]
	,a.Collected_Date [Date]
	,dp.Product_Category_Reporting [Product Category]
	,CASE WHEN dp.CSKU_Flag = 'C-SKU' THEN 'C-SKU'
		WHEN (dp.Government_SKU_Flag = 'Government SKU' AND dp.Product_Category_Reporting = 'Supplies') THEN 'G-SKU'
		WHEN dp.Product_Line = '4X' THEN 'Scanjet'	-- Scanjet Inclusion
		ELSE dp.Product_Type_Indirect_MAP 
		END [Product Subcategory]
	,CASE WHEN dp.Product_Type_Indirect_MAP IN ('Ink','Toner') THEN 'Ink & Toner' 
	      WHEN dp.Product_Type_Indirect_MAP LIKE 'Large Format%' THEN 'Large Format' 
		  WHEN dp.Product_Line = '4X' THEN 'Scanjet'	-- Scanjet Inclusion
		  ELSE dp.Product_Type_Indirect_MAP 
		  END [Product Subcategory Enforcement]
	,a.SKU
	,UPPER(COALESCE(nm.[ASIN],nmi.[ASIN],REPLACE(syn.[ASIN],'N/A',NULL)) )[ASIN]
	,a.Product_Description
	,sel.Seller_Name_Unified [Account]
	,a.Seller_Name [Seller Name]
	,a.Master_New_Location_Id [Location ID] 
	,rg.Penalty_Type [Seller Penalty Type]
	,a.Market [Market]
	,Login_Type [Log-in Type]
	,Price_Location_Unified [Price Location]
	,a.MAP
	,a.Seller_Advertised_Price [Advertised Price]
	,a.IR [Eligible IR]
	,a.LPP [Lowest Possible Price]
	,a.Screenshot_URL
	,ISNULL(a.[Validation Status],'Not Inspected') [Validation_Status_Raw]
	,CASE WHEN a.Market IN ('Websites US','Best Buy') --CH 9/24/19 Added Best Buy 
					OR (a.Market = 'Amazon' AND a.Master_New_Location_Id = '10322374')
					OR (a.Market = 'Newegg' AND a.Master_New_Location_Id = '10319396')
					OR (a.Market = 'Walmart' AND a.Master_New_Location_Id = '10256711')
					THEN 1 
		WHEN a.Market = 'Amazon' THEN 2 
		WHEN a.Market = 'Walmart' THEN 3 
		WHEN a.Market = 'eBay' THEN 4 
		WHEN a.Market = 'Newegg' THEN 5 
		ELSE 6 
		END Market_ID
	,ISNULL(rr.Reason_Description,a.Notes) [Notes]	--CH 6/13/19 Add for rejection reasons (Notes contains other notes, not solely rejection reasons)
	,Tier_Pass_Through
	,a.Master_SID
	,a.Flag_Bundle
	,CASE WHEN Login_Type = 'Free log-in' THEN 3 ELSE 1 END Login_Type_ID
	,ISNULL(fact.Flag_StrikeThrough,0) Flag_StrikeThrough
INTO #CTE_Adhoc
FROM #DailyViolations a 
JOIN #Listings fact 
	ON	a.Fact_ID = fact.ID
JOIN _final.Dim_Product dp WITH(NOLOCK) 
	ON	a.SKU = dp.SKU
	AND dp.Flag_Current = 1 
	AND (dp.In_MAP_Scope_Flag = 'In MAP Scope' OR dp.Product_Line = '4X')	-- Scanjet Inclusion
JOIN _final.Dim_Date dt WITH(NOLOCK) 
	ON	a.Collected_Date = dt.Full_Date
LEFT JOIN _ref.Seller_Reporting_Group rg WITH(NOLOCK) 
	ON	a.Master_SID = rg.Master_SID
	AND a.Product_Type_Indirect_MAP = rg.Product_Type 
	AND a.Collected_Date BETWEEN rg.Valid_From AND rg.Valid_To
LEFT JOIN _ref.Rejection_Reasons rr WITH(NOLOCK) 
	ON	a.Notes = CAST(rr.Reason_ID AS NVARCHAR)  -- LU 8/6/20 Added due to BG Team request to use Reason IDs instead of Notes in _temp table. 
LEFT JOIN _final.Seller_Pricing_NewMo nm WITH(NOLOCK)
	ON	nm.ID = fact.NewMo_Source_Row_ID
LEFT JOIN _final.Seller_Pricing_NewMo_Intraday nmi WITH(NOLOCK) 
	ON	nmi.ID = fact.NewMo_Intraday_Source_Row_ID
LEFT JOIN _final.Seller_Pricing_Syndigo syn WITH(NOLOCK) 
	ON  syn.ID = fact.Syndigo_Source_Row_ID
LEFT JOIN _final.Dim_Seller sel WITH(NOLOCK) 
	ON fact.Seller_ID = sel.Seller_ID

CREATE NONCLUSTERED INDEX IX_CTE_Adhoc_Location_ID_SKU_Week ON #CTE_Adhoc([Location ID], SKU, [Week]);

DROP TABLE IF EXISTS #CTE_Vtable
SELECT a.Fact_ID [Fact ID]
	,Data_Source_ID
	,a.Week_Start_Date [Week]
	,a.Collected_Date [Date]
	,a.Product_Category_Reporting [Product Category]
	,CASE WHEN CSKU_Flag = 'C-SKU' THEN 'C-SKU'
		WHEN (Government_SKU_Flag = 'Government SKU' AND Product_Category_Reporting = 'Supplies') THEN 'G-SKU'
		WHEN Product_Line = '4X' THEN 'Scanjet'	-- Scanjet Inclusion
		ELSE Product_Type_Indirect_MAP_Dim_Product 
		END  [Product Subcategory]
	,CASE WHEN Product_Type_Indirect_MAP_Dim_Product IN ('Ink','Toner') THEN 'Ink & Toner' 
		  WHEN Product_Type_Indirect_MAP_Dim_Product LIKE 'Large Format%' THEN 'Large Format' 
		  WHEN Product_Line = '4X' THEN 'Scanjet'	-- Scanjet Inclusion
		  ELSE Product_Type_Indirect_MAP_Dim_Product 
		  END [Product Subcategory Enforcement]
	,SKU
	,[ASIN]
	,Product_Description
	,Seller_Name_Unified [Account]
	,Seller_Name [Seller Name]
	,New_Location_ID [Location ID]
	,Seller_Penalty_Type [Seller Penalty Type]
	,Market_Unified [Market]
	,CASE WHEN ISNULL(a.Login_Type_ID, 1) = 3 THEN 'Free log-in' ELSE 'Public Site' END [Log-in Type] 
	,Price_Location [Price Location]
	,MAP
	,Seller_Advertised_Price [Advertised Price]
	,Eligible_IR_Amount [Eligible IR]
	,Lowest_Possible_Price [Lowest Possible Price]
	,Screenshot_URL
	,CASE WHEN EXISTS(SELECT * FROM #CTE_Adhoc ad WHERE ad.[Location ID] = a.New_Location_ID AND ad.SKU = a.SKU AND ad.[Week] = a.Week_Start_Date) 
		THEN 'Not Inspected' ELSE ISNULL(Validation_Status,'Not Inspected') END [Validation_Status_Raw] --if Adhoc already processed, then take away any other inspection results for week; Not Insp to get derived later on
	,CASE WHEN Market IN ('Websites US','Best Buy') 
					OR (Market = 'Amazon' AND New_Location_ID = '10322374')
					OR (Market = 'Newegg' AND New_Location_ID = '10319396')
					OR (Market = 'Walmart' AND New_Location_ID = '10256711')
					THEN 1 
				WHEN Market = 'Amazon' THEN 2
				WHEN Market = 'Walmart' THEN 3
				WHEN Market = 'eBay' THEN 4
				WHEN Market = 'Newegg' THEN 5 ELSE 6 END Market_ID
	,Reason_Description --CH 6/13/19 Add for rejection reasons
	,Tier_Pass_Through
	,Master_SID cte
	,a.Flag_Bundle
	,ISNULL(a.Login_Type_ID, 1) Login_Type_ID
	,Flag_StrikeThrough
	,a.Violation_Type
INTO #CTE_Vtable
FROM(
	SELECT a.*
		,fact.Data_Source_ID
		,UPPER(COALESCE(nm.[ASIN],nmi.[ASIN],REPLACE(syn.[ASIN],'N/A',NULL)) )[ASIN]
		,Product_Description
--		,b.Product_Category_Reporting
		,b.CSKU_Flag
		,b.Government_SKU_Flag
		,b.Product_Type_Indirect_MAP [Product_Type_Indirect_MAP_Dim_Product]
		,0 AS [Matching Flag]
		,ROW_NUMBER() OVER(PARTITION BY a.[New_Location_ID],a.Collected_Date, b.SKU, ISNULL(a.Login_Type_ID, 1) ORDER BY REPLACE(ISNULL(Validation_Status,'Z'),'Not Inspected','Z')
																								,CASE WHEN a.Market IN ('Websites US','Best Buy')
																										OR (a.Market = 'Amazon' AND a.New_Location_ID = '10322374')
																										OR (a.Market = 'Newegg' AND a.New_Location_ID = '10319396')
																										OR (a.Market = 'Walmart' AND a.New_Location_ID = '10256711')
																										THEN 1 
																									WHEN a.Market = 'Amazon' THEN 2
																									WHEN a.Market = 'Walmart' THEN 3
																									WHEN a.Market = 'eBay' THEN 4
																									WHEN a.Market = 'Newegg' THEN 5 
																								ELSE 6 END--when multiple markets, etc
																								,Violation_Code --CH 7/16/21 adding to prioritize MAP, then CSKU, then QC; duplicate Fact IDs in ViolationsMAP due to moving QC under MAP
																								) [Violation ID Selector] 
		,ISNULL(hpres.Reason_Description,res.Reason_Description) [Reason_Description] --CH 6/13/19 Add for rejection reasons -- LU/8/28/20 Add for HP Reasons froim Admin Tool - prioritizing over DSM Reason
	    ,ISNULL(fact.Flag_StrikeThrough,0) Flag_StrikeThrough
	FROM #Violations a
	JOIN #Listings fact 
		ON  fact.ID = a.Fact_ID
	JOIN _final.Dim_Product b WITH(NOLOCK) 
		ON b.SKU = a.SKU 
		AND b.Flag_Current = 1 
		--AND b.In_MAP_Scope_Flag = 'In MAP Scope'
		AND (b.In_MAP_Scope_Flag = 'In MAP Scope' OR b.Product_Line = '4X')	-- Scanjet Inclusion
	LEFT JOIN _ref.Rejection_Reasons res WITH(NOLOCK) ON res.Reason_ID = a.Reason_ID
	LEFT JOIN _ref.HP_Rejection_Reasons hpres WITH(NOLOCK) ON hpres.HP_Reason_ID = a.HP_Reason_ID
	LEFT JOIN _final.Seller_Pricing_NewMo nm WITH(NOLOCK) ON nm.ID = fact.NewMo_Source_Row_ID
	LEFT JOIN _final.Seller_Pricing_NewMo_Intraday nmi WITH(NOLOCK) ON nmi.ID = fact.NewMo_Intraday_Source_Row_ID
	LEFT JOIN _final.Seller_Pricing_Syndigo syn WITH(NOLOCK) ON syn.ID = fact.Syndigo_Source_Row_ID
	WHERE a.Collected_Date < CAST(GETDATE() AS DATE)    -- 4/6/20 LU: due to intraday launch, need to restrict violations from current date
		AND NOT EXISTS(SELECT * FROM #CTE_Adhoc ad WHERE ad.[Location ID] = a.New_Location_ID AND ad.SKU = a.SKU AND ad.[Date] = a.Collected_Date)
	)a
WHERE [Violation ID Selector] = 1
	AND [Matching Flag] = 0

CREATE NONCLUSTERED INDEX IX_CTE_Vtable_Location_ID_SKU_Week ON #CTE_Vtable([Location ID], SKU, [Week]);

DROP TABLE IF EXISTS #CTE_fact
SELECT	A.ID Fact_ID
	    ,Data_Source_ID
		,Week_Begin_Date_Alt [Week]
		,CAST(Collected_Date AS DATE) [Date]
		,[Product Category]
		,CASE WHEN CSKU_Flag = 'C-SKU' THEN 'C-SKU'
			  WHEN (Government_SKU_Flag = 'Government SKU' AND [Product Category] = 'Supplies') THEN 'G-SKU'
			  WHEN Product_Line = '4X' THEN 'Scanjet'	-- Scanjet Inclusion
			  ELSE [Product Subcategory] END [Product Subcategory]
		,CASE WHEN [Product Subcategory]  IN ('Ink','Toner') THEN 'Ink & Toner' 
		      WHEN [Product Subcategory] LIKE 'Large Format%' THEN 'Large Format'
			  WHEN Product_Line = '4X' THEN 'Scanjet'	-- Scanjet Inclusion
		      ELSE [Product Subcategory]  END [Product Subcategory Enforcement]
		,SKU
		,[ASIN]
		,Product_Description
		,Seller_Name_Unified [Account]
		,[Seller Name]
		,Master_New_Location_Id [Location ID]
		,Penalty_Type [Seller Penalty Type]
		,a.Market
		,Login_Type [Log-in Type]
		,Price_Location_Unified [Price Location]
		,MAP
		,Seller_Advertised_Price [Advertised Price]
		,IR [Eligible IR]
		,LPP [Lowest Possible Price]
		,Screenshot_URL
		,'Not Inspected' [Validation_Status_Raw]
		,CASE WHEN a.Market IN ('Websites US','Best Buy')
					OR (a.Market = 'Amazon' AND Master_New_Location_Id = '10322374')
					OR (a.Market = 'Newegg' AND Master_New_Location_Id = '10319396')
					OR (a.Market = 'Walmart' AND Master_New_Location_Id = '10256711')
					THEN 1 
				WHEN Market = 'Amazon' THEN 2
				WHEN Market = 'Walmart' THEN 3
				WHEN Market = 'eBay' THEN 4
				WHEN Market = 'Newegg' THEN 5 ELSE 6 END Market_ID
		,CAST(NULL AS nvarchar) [Notes]--CH 6/13/19 Add for rejection reasons - fact won't have any
		,Tier_Pass_Through
		,Master_SID
		,a.Flag_Bundle
		,ISNULL(a.Login_Type_ID, 1) Login_Type_ID
		,ISNULL(Flag_StrikeThrough,0) Flag_StrikeThrough
INTO #CTE_fact
FROM(
	SELECT fact.*
		,sel.Seller_Name_Unified
		,brs.Seller_Name [Seller Name]
		,sel.Master_New_Location_Id
		,sel.Master_SID
		,prdc.Product_Category_Reporting [Product Category]
		,prdc.Product_Type_Indirect_MAP [Product Subcategory]
		,prd.SKU
		,prd.CSKU_Flag
		,prd.Government_SKU_Flag
		,prd.Product_Line	-- Scanjet Inclusion
		,UPPER(COALESCE(nm.[ASIN],nmi.[ASIN],REPLACE(syn.[ASIN],'N/A',NULL)) )[ASIN]
		,prd.Product_Description
		,dt.Week_Begin_Date_Alt
		,rg.Penalty_Type
		,CASE WHEN mkt.Market = 'Best Buy' THEN 'Websites US' ELSE mkt.Market_Unified END Market
		,lg.Login_Type
		,Price_Location_Unified
		,0 AS [Matching Flag]
		,vc.ViolationCode AS [Violation_Code] --NE 10/06/22 Tier change -- 07/11/23 ED: Removing Violation Code 7
		,ROW_NUMBER() OVER(PARTITION BY sel.Master_New_Location_ID,CAST(fact.Collected_Date AS DATE), prd.SKU, ISNULL(fact.Login_Type_ID, 1) ORDER BY CASE WHEN mkt.Market IN ('Websites US','Best Buy')
																											OR (mkt.Market = 'Amazon' AND sel.Master_New_Location_ID = '10322374')
																											OR (mkt.Market = 'Newegg' AND sel.Master_New_Location_ID = '10319396')
																											OR (mkt.Market = 'Walmart' AND sel.Master_New_Location_ID = '10256711')
																											THEN 1 
																										WHEN mkt.Market = 'Amazon' THEN 2
																										WHEN mkt.Market = 'Walmart' THEN 3
																										WHEN mkt.Market = 'eBay' THEN 4
																										WHEN mkt.Market = 'Newegg' THEN 5 
																										ELSE 6 END--when multiple markets, etc
																										,vc.ViolationCode --NE 10/06/22 Tier change
																										) [Violation ID Selector]
	FROM	#Listings fact
	JOIN	_final.Dim_Date dt WITH(NOLOCK) 
		ON	CAST(fact.Collected_Date as date) = dt.Full_Date	
	JOIN	_final.Dim_Seller sel WITH(NOLOCK) 
		ON	fact.Seller_ID = sel.Seller_ID
	JOIN	_final.Dim_Product prd WITH(NOLOCK) 
		ON	fact.Product_ID = prd.Product_ID
	JOIN	_final.Dim_Product prdc WITH(NOLOCK) 
		ON	prd.SKU = prdc.SKU 
		AND prdc.Flag_Current=1
	JOIN	_final.Dim_Price_Location loc WITH(NOLOCK) 
		ON	fact.Price_Location_ID = loc.Price_Location_ID
	JOIN	_final.Dim_Product_Condition cond WITH(NOLOCK) 
		ON	fact.Product_Condition_ID = cond.Product_Condition_ID
	JOIN	_final.Dim_Market mkt WITH(NOLOCK) 
		ON	fact.Market_ID = mkt.Market_ID
	JOIN	_final.Dim_Login_Type lg WITH(NOLOCK) 
		ON	lg.Login_Type_ID = ISNULL(fact.Login_Type_ID,1)
	LEFT JOIN _ref.Seller_Reporting_Group rg WITH(NOLOCK) 
		ON	rg.Master_SID = sel.Master_SID
		AND rg.Product_Type = prd.Product_Type_Indirect_MAP
		AND fact.Collected_Date >= rg.Valid_From 
		AND fact.Collected_Date < CASE WHEN rg.Valid_To = '9999-12-31' THEN rg.Valid_To ELSE DATEADD(D,1,rg.Valid_To) END
	LEFT JOIN _final.Bridge_Sellers brs WITH(NOLOCK) 
		ON	fact.Seller_Name_ID = brs.Seller_Name_ID 
		AND brs.Flag_Current = 1  -- 10/30/2020 LU added to include Seller Name detail
	LEFT JOIN _ref.Marketplace_Approved mpa WITH(NOLOCK) 
		ON	mpa.New_Location_ID = brs.Master_New_Location_Id --CH 7/16/21: adding new marketplace tables to bring in QC
		AND mpa.Market_Unified = mkt.Market_Unified
		AND CAST(Fact.Collected_Date AS date) BETWEEN mpa.Valid_From AND mpa.Valid_To
		AND mpa.Country = 'US'
		AND mpa.Flag_Active = 1
	LEFT JOIN _ref.Seller_Market_Mapping smm WITH(NOLOCK) 
		ON brs.Seller_Name_Unified = smm.Seller_Name_Unified			--CH 7/16/21: adding new marketplace tables to bring in QC											
		AND mkt.Market_Unified = smm.Market_Unified
	LEFT JOIN	_final.Seller_Pricing_NewMo nm WITH(NOLOCK)
		ON nm.ID = fact.NewMo_Source_Row_ID
	LEFT JOIN	_final.Seller_Pricing_NewMo_Intraday nmi WITH(NOLOCK) 
		ON	nmi.ID = fact.NewMo_Intraday_Source_Row_ID
	LEFT JOIN	_final.Seller_Pricing_Syndigo syn WITH(NOLOCK) 
		ON	syn.ID = fact.Syndigo_Source_Row_ID

	CROSS APPLY dbo.TVF_GET_VIOLATION_CODE_EPC(
		fact.Seller_Advertised_Price,
		fact.IR,
		fact.MAP,
		fact.PC,
		prd.CSKU_Flag,
		fact.Tier_Pass_Through,
		prd.Product_Category_Reporting,
		fact.Flag_Bundle,
		fact.Strikethrough_Price,
		fact.Coupon_Discount_Price
	) AS vc	-- New FN

	WHERE 
			prd.In_MAP_Scope_Flag = 'In MAP Scope'
			AND loc.In_MAP_Scope_Flag = 'In MAP Scope'
			AND mkt.In_MAP_Scope_Flag = 'In MAP Scope'
			AND lg.In_MAP_Scope = 'In MAP Scope'
			AND vc.ViolationCode IS NOT NULL
			AND fact.Collected_Date < CAST(GETDATE() AS DATE)   -- 4/6/20 LU: due to intraday launch, need to restrict violations from current date
			AND fact.Data_Source_ID <> 6  
			AND NOT EXISTS(SELECT * 
							FROM #CTE_Vtable v
							WHERE fact.Collected_Date >= v.[Date]
									AND fact.Collected_Date < DATEADD(D,1,v.[Date])
									AND v.[Location ID] = sel.Master_New_Location_Id	--CH 11/4/19 added to account for HP; not in ViolationsMAP
									AND v.SKU = prd.SKU) --added detail on SKU to account for LF/LFS not in ViolMAP for Dir/VPA; 9/22 these have been added
			AND NOT EXISTS(SELECT * 
							FROM #CTE_Adhoc ad
							WHERE ad.[Location ID] = sel.Master_New_Location_Id 
									AND ad.SKU = prd.SKU 
									AND fact.Collected_Date >= ad.[Date]
									AND fact.Collected_Date < DATEADD(D,1,ad.[Date]))
			--AND fact.Quantity = 1
	) a
WHERE [Violation ID Selector] = 1
		AND [Matching Flag] = 0

CREATE NONCLUSTERED INDEX IX_CTE_Fact_Location_ID_SKU_Week ON #CTE_fact([Location ID], SKU, [Week]);

DROP TABLE IF EXISTS #CTE_Status --grabbing active status
SELECT DISTINCT a.[ID]
	,a.[Notification_ID]
	,a.[Seller Name]
	,a.[New Location ID]
	,a.[Group]
	,a.[Product Line]
	,a.[Product_Type]
	,a.[Supplies_Qualification]
	,a.[Print_Qualification]
	,a.[Notification_Approval_Status]
	,a.[Letter Sent Date]
	,a.[Letter Delivered Date]
	,a.[Letter Tracking Num]
	,a.[Letter Type]
	,a.[Comments]
	,a.[Buffer Period Start]
	,a.[Buffer Period End]
	,a.[Penalty Period Start]
	,a.[Penalty Period End]
	,a.[Product Suspension Start]
	,a.[Product Suspension End]
	,a.[MAP Status]
	,a.[MAP Status Detail]
	,a.[Rehab Flag]
	,a.[Annual Revenue]
	,a.[60-day Product Suspension Impact]
	,a.[180-day Product Suspension Impact]
	,a.[Product Suspension Impact]
	,a.[DGF Penalty]
	,a.[Account Owner]
	,a.[Active Flag]
	,a.[Repeat Offender Flag]
	,a.[Contact Channel]
	,a.[Program]
	,a.[Marketplace Suspension Flag]
	,a.[MPA Letter Delivered Date]
	,a.[Country]
	,a.[Restricted SKU Enforcement]
	,a.[Seller Reporting Group]
	,a.[Notification Generation Date]
	,a.[Product Line_QDN Tool]
	,b.Product_Category
	,CASE WHEN a.Product_Type = 'Large Format Supplies' THEN a.Product_Type ELSE b.Product_Subcategory END Product_Subcategory
INTO #CTE_Status
FROM _report.VI_MAP_QC_Status a WITH (NOLOCK)
LEFT JOIN #Product_Category b ON CASE WHEN b.Product_Category LIKE '%Supplies' THEN 'Ink & Toner'
                                      WHEN b.Product_Subcategory LIKE '%Large Format' THEN 'Large Format'
									  ELSE b.Product_Subcategory END = CASE WHEN a.[Product Line] = 'HPS Printers' THEN 'Inkjet'
									                                        WHEN a.[Product Line] = 'OPS Printers' THEN 'LaserJet'
																			WHEN a.[Product Line] = 'Toner' THEN 'Ink & Toner'
																			ELSE a.[Product Line] END
WHERE a.Program = 'MAP'
	 AND a.Notification_ID IS NOT NULL
	 AND a.[Active Flag] = 'Active'
	 AND a.[Letter Type] <> 'Courtesy Alert'

CREATE NONCLUSTERED INDEX IX_CTE_Status ON #CTE_Status ([New Location ID], [Product_Subcategory]);

DROP TABLE IF EXISTS #CTE_Union --combining each of the three, then applying derived VI results
SELECT CASE WHEN [Validation_Status_Raw] = 'Not Inspected'
			THEN CASE WHEN MAX(CASE WHEN [Validation_Status_Raw] = 'Accepted' THEN 1 ELSE 0 END) OVER(PARTITION BY [Week],[Location ID],SKU,Login_Type_ID) = 1 THEN 'Accepted - Derived'
					WHEN MAX(CASE WHEN [Validation_Status_Raw] = 'Rejected' THEN 1 ELSE 0 END) OVER(PARTITION BY [Week],[Location ID],SKU,Login_Type_ID) = 1 THEN 'Rejected - Derived' 
					ELSE Validation_Status_Raw END
		ELSE [Validation_Status_Raw]
		END [Validation Status]
	,CASE WHEN MAX(CASE WHEN [Validation_Status_Raw] = 'Accepted' THEN 1 ELSE 0 END) OVER(PARTITION BY [Week],[Location ID],SKU,Login_Type_ID) = 1 THEN 'Accepted'
					WHEN MAX(CASE WHEN [Validation_Status_Raw] = 'Rejected' THEN 1 ELSE 0 END) OVER(PARTITION BY [Week],[Location ID],SKU,Login_Type_ID) = 1 THEN 'Rejected' 
					ELSE Validation_Status_Raw END [Validation Status Weekly]
	,a.*
INTO #CTE_Union
FROM (
	SELECT *
		,'N/A' AS Violation_Type
		,DENSE_RANK() OVER(ORDER BY Week DESC) [Adhoc Week Selector]
	FROM #CTE_Adhoc

	UNION

	SELECT * 
		,0 
	FROM #CTE_Vtable

	UNION 

	SELECT *
		,'N/A' AS Violation_Type
		,-1 
	FROM #CTE_Fact
) a

CREATE NONCLUSTERED INDEX IX_CTE_Union ON #CTE_Union ([Location ID], Master_SID, [Date], [Product Subcategory]);

--G20 seller only crossjoin
DROP TABLE IF EXISTS #CTE_cj
	SELECT DISTINCT a.*	
		,b.*
		,c.*
		,ISNULL(rg.Penalty_Type,'30, 60, 90 Suspension') [Seller Penalty Type]
		,ISNULL(rg.Reporting_Group,'Rest of Channel') [Reporting Group]   -- 3/6 LU Added for MPA Reporting Group
	INTO #CTE_cj
	FROM #Weeks a
	CROSS APPLY (
		SELECT DISTINCT Product_Category_Reporting [Product Category]
			,Product_Type_Indirect_MAP [Product Subcategory]
		FROM _final.Dim_Product p WITH(NOLOCK) --switching to Dim since LF,PW,SJ will not come through if no violations
		WHERE ((p.Product_Category_Reporting IN ('Print','Supplies','CPS','BPS')
					AND (p.In_MAP_Scope_Flag = 'In MAP Scope' OR p.Product_Line = '4X'))	-- Scanjet Inclusion
					AND p.Flag_Current=1)
		UNION
		SELECT 'Supplies' AS [Product Category], --DP 10/19/22 adding C-SKU to cj to separate restricted ink/toner
		'C-SKU' AS [Product Subcategory]
		UNION
		SELECT 'Supplies' AS [Product Category],
		'G-SKU' AS [Product Subcategory]
	)b
	CROSS APPLY 
	(
		SELECT DISTINCT
		[Account]
		,ISNULL(sft.StoreFrontName,'Seller not Marketplace Approved') [Storefront Name(s)]    -- 3/20 LU added for Storefront Name(s)
		,[Location ID]
		,Master_SID
		FROM #CTE_Union u --pulling only g20 sellers?
		LEFT JOIN #StoreFrontNames sft ON u.[Location ID] = sft.New_Location_ID AND sft.Country = 'US'         -- 3/20 LU Adding Storefront Name(s)
	)c
	LEFT JOIN _ref.Seller_Reporting_Group rg WITH(NOLOCK) ON rg.Master_SID = c.Master_SID
		AND a.Date BETWEEN rg.Valid_From AND rg.Valid_To
		AND rg.Product_Type = CASE WHEN b.[Product Subcategory] IN ('C-SKU','G-SKU') THEN 'Toner' ELSE b.[Product Subcategory] END

CREATE NONCLUSTERED INDEX IX_CTE_cj ON #CTE_cj (Master_SID, [Date], [Product Subcategory], [Location ID]);

--Pulling Contacts for report tooltip & covered/uncovered split
DROP TABLE IF EXISTS #CTE_Contacts
SELECT DISTINCT a.Account [Seller Name Unified]
	,a.[Location ID] [New Location ID]
	,a.[Product Category]
	,rep1.Rep AS HP_Rep1
	,rep2.Rep AS HP_Rep2
	,rep3.Rep AS HP_Rep3
	,rep4.Rep AS HP_Rep4
	,rep5.Rep AS HP_Rep5
	,rep6.Rep AS HP_Rep6
	,LOWER(i.HP_Rep_1_Email) AS Email1
	,LOWER(i.HP_Rep_2_Email) AS Email2
	,LOWER(i.HP_Rep_3_Email) AS Email3
	,LOWER(i.HP_Rep_4_Email) AS Email4
	,LOWER(i.HP_Rep_5_Email) AS Email5
	,LOWER(i.HP_Rep_6_Email) AS Email6
INTO #CTE_Contacts
FROM (SELECT DISTINCT [Location ID]
                      ,Account
					  ,CASE WHEN [Product Subcategory] LIKE 'Large Format%' THEN 'Large Format'
							ELSE [Product Category] END [Product Category]
					  ,[Product Subcategory] 
      FROM #CTE_cj) a
LEFT JOIN VI_SELLERS_EMAIL_INFO_ALL i WITH(NOLOCK) 
	ON 
		i.New_Location_ID = a.[Location ID]
	AND CASE WHEN i.Product_Type IN ('CPS','BPS') THEN i.Product_Type ELSE i.Product_Category END = CASE WHEN i.Product_Type = 'All' AND i.Product_Category = 'PC' AND a.[Product Category] IN ('CPS','BPS') THEN 'PC' ELSE a.[Product Category] END
	AND i.Source_Rank = 1
LEFT JOIN _report.Seller_Email_Union rep1 WITH(NOLOCK) ON i.HP_Rep_1_Email = rep1.Email
LEFT JOIN _report.Seller_Email_Union rep2 WITH(NOLOCK) ON i.HP_Rep_2_Email = rep2.Email
LEFT JOIN _report.Seller_Email_Union rep3 WITH(NOLOCK) ON i.HP_Rep_3_Email = rep3.Email
LEFT JOIN _report.Seller_Email_Union rep4 WITH(NOLOCK) ON i.HP_Rep_4_Email = rep4.Email
LEFT JOIN _report.Seller_Email_Union rep5 WITH(NOLOCK) ON i.HP_Rep_5_Email = rep5.Email
LEFT JOIN _report.Seller_Email_Union rep6 WITH(NOLOCK) ON i.HP_Rep_6_Email = rep6.Email

-- OUTPUT (all G20 sellers + nonG20 for just CSKUs)
DROP TABLE IF EXISTS #output_prep
SELECT DISTINCT 
	CAST('US' AS nvarchar(10)) [Country]
	, a.* 
	,CASE WHEN g20.ID IS NOT NULL THEN 1 ELSE 0 END [G20 Sel/Cat Flag]
	,ROW_NUMBER() OVER(PARTITION BY a.[Location ID], a.Week, ISNULL(a.SKU,[Product Subcategory]), Login_Type_ID ORDER BY REPLACE(ISNULL([Validation Status],'Z'),'Not Inspected','Z')) [Weekly Violation Selector]  -- 9/17/2020 LU: Moved up a line, certain weeks weren't getting a WVS of 1
	,Fiscal_Week_Number [Fiscal Week Number]
INTO #output_prep
FROM
(
	SELECT a.*
			,ROW_NUMBER() OVER(PARTITION BY a.[Location ID],a.Date, ISNULL(a.SKU,[Product Subcategory]), Login_Type_ID ORDER BY [Letter Type] DESC)[Selector]
			,0 AS [Matching Flag]
		FROM 
		(
			SELECT 
				--DISTINCT
				[Validation Status]
				, [Validation Status Weekly]
				, a.[Week]
				, a.[Date]
				, a.[Product Category]
				, a.[Product Subcategory]
				, d.[Product Subcategory Enforcement]
				, [Fact ID]
				,Data_Source_ID
				, d.SKU
				, d.[ASIN]
				, d.Product_Description
				, CASE WHEN a.[Account] = 'Target' THEN 'Target Corporation' ELSE a.Account END [Account]
				, d.[Seller Name]
				, [Storefront Name(s)]  -- 3/20 LU Adding StoreFront Name(s)
				, a.[Location ID]
				, CASE WHEN qpp.Account IS NOT NULL THEN dbo.FN_GET_SELLER_STATUS (a.[Product Category], sel.Supplies_Qualification, sel.Print_Qualification,sel.Qualified_Business_Personal_Systems,sel.Qualified_Consumer_Personal_Systems) 
					   ELSE 'Unauthorized' END Seller_Status
	            ,CASE WHEN qpp.[Status] = 'Dropped' THEN qpp.Drop_Date  
	                  WHEN qpp.Action_Required = 'PA Termination' THEN qpp.Expiration_Date
		              ELSE NULL END [Termination Date]
				, a.[Seller Penalty Type]
				, a.[Reporting Group]   -- 3/6 LU Added for MPA Reporting Group
				, [Market]
				, [Log-in Type]
				, [Price Location]
				, MAP
				, [Advertised Price]
				, [Eligible IR]
				, [Lowest Possible Price]
				, [Validation_Status_Raw]
				, e.[Letter Type]
				, CAST(ISNULL(e.[MAP Status Detail],'N/A') AS NVARCHAR(MAX)) [MAP Status Detail]
				, e.[Letter Delivered Date]
				, e.[Notification Generation Date]
				, e.[Buffer Period Start]
				, e.[Buffer Period End]
				, e.[Product Suspension Start]
				, e.[Product Suspension End]
				, e.[Penalty Period Start]
				, e.[Penalty Period End]
				, Screenshot_URL
				--, ISNULL([Adhoc Week Selector],MAX([Adhoc Week Selector])OVER(PARTITION BY a.Week))[Adhoc Week Selector]
				, [DGF Penalty]
				, Notes
				,d.Tier_Pass_Through
				,CASE WHEN a.[Location ID] = '99999999' THEN 1 ELSE Threshold_Action END [Category Threshold Highlight]  -- Want to apply a threshold of 1 for HP
				,CASE WHEN a.[Location ID] = '99999999' THEN 1 ELSE Threshold_Action END [Category Threshold Alert]
				,gc.HP_Rep1
				,gc.HP_Rep2
				,gc.HP_Rep3
				,gc.HP_Rep4
				,gc.HP_Rep5
				,gc.HP_Rep6
				,gc.Email1
				,gc.Email2
				,gc.Email3
				,gc.Email4
				,gc.Email5
				,gc.Email6
				,d.Flag_Bundle
				,ISNULL(d.Login_Type_ID, 1) Login_Type_ID
				,ISNULL(d.Flag_StrikeThrough,0) Flag_StrikeThrough
				,d.Violation_Type
			FROM #CTE_cj a --DP 10/18/22 updating to merged CJ for CSKUs
			LEFT JOIN #CTE_Union d
				ON	d.Master_SID = a.Master_SID --rv 4/12/23
				AND d.[Product Subcategory] = a.[Product Subcategory] 
				AND d.Date = a.Date
			LEFT JOIN #CTE_Status e 
				ON	e.[New Location ID] = a.[Location ID]
				AND CASE WHEN a.[Product Subcategory] = 'Large Format Supplies' THEN 'Large Format' ELSE a.[Product Subcategory] END = CASE WHEN e.[Product_Subcategory] = 'Large Format Supplies' THEN 'Large Format'  ELSE e.[Product_Subcategory] END
			LEFT JOIN _final.Dim_Seller sel WITH(NOLOCK) 
				ON	a.[Location ID] = sel.Master_New_Location_Id 
				AND sel.Flag_Current = 1
			LEFT JOIN _ref.Violation_Rules vr WITH(NOLOCK) 
				ON vr.Program = 'MAP'
				        AND a.[Reporting Group] = vr.Seller_Group
						AND a.[Seller Penalty Type] = vr.Penalty_Description
						AND CASE WHEN a.[Product Subcategory] IN ('C-SKU','G-SKU') THEN 'Toner' ELSE a.[Product Subcategory] END = CASE WHEN vr.Product_Type_Hybrid = 'HPS Printers' THEN 'Inkjet' WHEN vr.Product_Type_Hybrid = 'OPS Printers' THEN 'LaserJet' ELSE vr.Product_Type_Hybrid END
						AND CASE WHEN e.[Letter Type] IS NULL THEN 'V1' 
								WHEN a.[Seller Penalty Type] NOT LIKE '%Financial' AND e.[Letter Type] = 'V1' THEN 'V2'
								WHEN a.[Seller Penalty Type] NOT LIKE '%Financial' AND e.[Letter Type] = 'V2' THEN 'V3'            -- Currently not necessary but accounting for possible Suspension length specific thresholds
								WHEN a.[Seller Penalty Type] NOT LIKE '%Financial' AND e.[Letter Type] IN ('V3','V4') THEN 'V4'	 -- Currently not necessary but accounting for possible Suspension length specific thresholds
							ELSE e.[Letter Type] END = vr.[Action]
						AND a.[Date] BETWEEN vr.Valid_From AND vr.Valid_To
			LEFT JOIN #CTE_Contacts gc 
				ON	a.[Location ID] = gc.[New Location ID]  -- 9/10/20 LU added for G20 Contacts
				AND CASE WHEN a.[Product Subcategory] LIKE 'Large Format%' THEN 'Large Format'
						WHEN a.[Product Subcategory] IN ('C-SKU','G-SKU') THEN 'Supplies' --DP 1/12/23 adjusting join so Supplies contacts apply to C-SKU in tooltip
						ELSE a.[Product Category] END = gc.[Product Category]	
			LEFT JOIN HP_QPP_Prod._web.tbl_Partner qpp WITH (NOLOCK) 
				ON	qpp.HPI_Location_ID = sel.Master_New_Location_Id 
				AND qpp.Flag_Active = 1 
				AND qpp.Flag_Current = 1
				AND qpp.[Status] = 'Active'
				AND qpp.Country = 'US'
			WHERE a.[Location ID] <> 'N/A'
		)a
) a
LEFT JOIN _ref.G20_Seller_Product g20 WITH(NOLOCK) ON g20.Master_New_Location_Id = a.[Location ID] --DP 10/18/22 updating to left join to pull in nonG20 CSKU sellers
	AND g20.Product_Type_Indirect_MAP = CASE WHEN a.[Product Subcategory] IN ('C-SKU', 'G-SKU') THEN 'Toner' ELSE a.[Product Subcategory] END
	AND g20.Valid_To = '9999-12-31' -- don't have flag current for table
LEFT JOIN #Fiscal_Week fw ON a.[Week] = fw.Week_Begin_Date_Alt
WHERE Selector = 1

CREATE NONCLUSTERED INDEX IX_output_prep ON #output_prep ([Location ID], [Week], [Product Subcategory]);

DROP TABLE IF EXISTS #live_link
SELECT a.[Fact ID]
       ,ISNULL(c.Listing_URL,'N/A') [Listing URL]
INTO #live_link
FROM #output_prep a
LEFT JOIN _final.Fact_Listings b WITH (NOLOCK) ON a.[Fact ID] = b.ID
LEFT JOIN _final.Seller_Pricing_NewMo c WITH (NOLOCK) ON c.ID = b.NewMo_Source_Row_ID
WHERE a.Screenshot_URL = 'N/A'

DROP TABLE IF EXISTS #output_prep2
SELECT 
	 a.[Country]
	,a.[Validation Status]
	,a.[Validation Status Weekly]
	,a.[Week]
	,a.[Date]
	,a.[Product Category]
	,a.[Product Subcategory]
	,a.[Product Subcategory Enforcement]
	,a.[Fact ID]
	,a.Data_Source_ID
	,a.[SKU]
	,a.[ASIN]
	,a.[Product_Description]
	,a.[Account]
	,a.[Seller Name]
	,a.[Storefront Name(s)]
	,a.[Location ID]
	,a.Seller_Status [Seller Status]
	,a.[Termination Date]
	,a.[Seller Penalty Type]
	,a.[Reporting Group]
	,a.[Market]
	,a.[Log-in Type]
	,a.[Price Location]
	,a.[MAP]
	,a.[Advertised Price]
	,a.[Eligible IR]
	,a.[Lowest Possible Price]
	,a.[Validation_Status_Raw]
	,a.[Letter Type]
	,a.[MAP Status Detail]
	,b.[Letter Delivered Date]
	,b.[Notification Generation Date]
	,b.[Buffer Period Start]
	,b.[Buffer Period End]
	,b.[Product Suspension Start]
	,b.[Product Suspension End]
	,b.[Penalty Period Start]
	,b.[Penalty Period End]
	,CASE WHEN ISNULL(a.[Screenshot_URL], 'N/A') = 'N/A' THEN c.[Listing URL] ELSE a.[Screenshot_URL] END [Screenshot_URL]
	,a.[DGF Penalty]
	,a.[Notes]
	,a.[Tier_Pass_Through]
	,CASE WHEN a.[Category Threshold Highlight] IS NULL AND a.[Seller Penalty Type] LIKE '%Financial' AND a.[Product Subcategory Enforcement] = 'Ink & Toner' THEN 5
	      WHEN a.[Category Threshold Highlight] IS NULL AND a.[Seller Penalty Type] LIKE '%Financial' AND a.[Product Subcategory Enforcement] IN ('Inkjet', 'LaserJet') THEN 2
	      ELSE a.[Category Threshold Highlight] END [Category Threshold Highlight]
	,CASE WHEN a.[Category Threshold Alert] IS NULL AND a.[Seller Penalty Type] LIKE '%Financial' AND a.[Product Subcategory Enforcement] = 'Ink & Toner' THEN 5
	      WHEN a.[Category Threshold Alert] IS NULL AND a.[Seller Penalty Type] LIKE '%Financial' AND a.[Product Subcategory Enforcement] IN ('Inkjet', 'LaserJet') THEN 2
	      ELSE a.[Category Threshold Alert] END [Category Threshold Alert]
	,a.[HP_Rep1]
	,a.[HP_Rep2]
	,a.[HP_Rep3]
	,a.[HP_Rep4]
	,a.[HP_Rep5]
	,a.[HP_Rep6]
	,a.[Email1]
	,a.[Email2]
	,a.[Email3]
	,a.[Email4]
	,a.[Email5]
	,a.[Email6]
	,a.[Selector]
	,a.[Matching Flag]
	,a.[G20 Sel/Cat Flag]
	,a.[Weekly Violation Selector]
	,a.[Fiscal Week Number]
	,CASE WHEN [Validation Status] LIKE 'Accepted%' AND [MAP Status Detail] NOT LIKE '%To be Sent' AND a.Date > ISNULL(b.[Buffer Period End],'1999-01-01') THEN 'Accepted - Contributing to Threshold'
			WHEN [Validation Status] LIKE 'Accepted%' AND (a.Date <= ISNULL(b.[Buffer Period End],'1999-01-01') OR [MAP Status Detail] LIKE '%To be Sent') THEN 'Accepted - Not Contributing to Threshold'
			ELSE [Validation Status] END [Validation Status New]  -- 04/28/23 ED: Adding 'Validation Status New' to diferentiate between accepted violations contr. to threshold vs not contr. to threshold
	, a.Flag_Bundle
	,CASE WHEN t.Master_New_Location_Id IS NOT NULL THEN 1 ELSE 0 END [Top_Reseller_Flag]
	,a.Login_Type_ID
	,a.Flag_StrikeThrough
	,a.Violation_Type
INTO #output_prep2
FROM #output_prep a
LEFT JOIN (SELECT DISTINCT [Week]             
		                ,[Product Subcategory]
						,[Account]
						,[Location ID]
						,[Letter Delivered Date]
						,[Notification Generation Date]
						,[Buffer Period Start]
						,[Buffer Period End]
						,[Product Suspension Start]
						,[Product Suspension End]
						,[Penalty Period Start]
						,[Penalty Period End]
		FROM #output_prep
		WHERE [Letter Delivered Date] IS NOT NULL) b ON a.[Location ID] = b.[Location ID]
			                                            AND a.[Week] = b.[Week]
																AND a.[Product Subcategory] = b.[Product Subcategory]
LEFT JOIN #live_link c ON a.[Fact ID] = c.[Fact ID]
LEFT JOIN _ref.Courtesy_Alerts_Top_Seller_List t WITH (NOLOCK) ON t.Master_New_Location_Id = a.[Location ID]
WHERE NOT (ISNULL(Data_Source_ID,100) = 8 AND (Seller_Status = 'Qualified' OR Seller_Status = 'Not Qualified'))
		AND NOT ([Date] < '2023-11-01' AND ISNULL(Data_Source_ID,100) = 10)

CREATE NONCLUSTERED INDEX IX_output_prep2 ON #output_prep2 ([Week], [Location ID], [Product Subcategory Enforcement], [Date]);

DROP TABLE IF EXISTS #output_prep3
SELECT a.*
    ,SUM(CASE WHEN b.SKU IS NOT NULL THEN 1 ELSE 0 END) OVER (PARTITION BY a.[Week], a.[Location ID], a.[Product Subcategory Enforcement] ORDER BY a.[Date] ) AS RunningTotal
    ,DENSE_RANK () OVER (ORDER BY a.Week DESC) [Rank Week]
INTO #output_prep3
FROM #output_prep2 a
LEFT JOIN (
		SELECT Week, MIN(Date) Min_Date, [Location ID], SKU
		FROM #output_prep2
		WHERE SKU IS NOT NULL
		GROUP BY Week, [Location ID], SKU
		) b
ON a.Week = b.Week 
	AND a.Date = b.Min_Date
	AND a.[Location ID] = b.[Location ID]
	AND a.SKU = b.SKU

CREATE NONCLUSTERED INDEX IX_output_prep3 ON #output_prep3 ([Location ID], SKU);

DROP TABLE IF EXISTS #output
SELECT [Country]
		,[Validation Status]
		,[Validation Status Weekly]
		,[Week]
		,[Date]
		,[Product Category]
		,[Product Subcategory]
		,[Product Subcategory Enforcement]
		,[Fact ID]
		,Data_Source_ID [Data Source ID]
		,a.[SKU]
		,[ASIN]
		,[Product_Description]
		,[Account]
		,[Seller Name]
		,[Storefront Name(s)]
		,[Location ID]
		,[Seller Status]
		,[Termination Date]
		,[Seller Penalty Type]
		,[Reporting Group]
		,[Market]
		,[Log-in Type]
		,[Price Location]
		,[MAP]
		,[Advertised Price]
		,[Eligible IR]
		,[Lowest Possible Price]
		,[Validation_Status_Raw]
		,[Letter Type]
		,[MAP Status Detail]
		,[Letter Delivered Date]
		,[Notification Generation Date]
		,[Buffer Period Start]
		,[Buffer Period End]
		,[Product Suspension Start]
		,[Product Suspension End]
		,[Penalty Period Start]
		,[Penalty Period End]
		,[Screenshot_URL]
		,CASE 
			WHEN 
					[Rank Week] = 1 
				AND [Seller Penalty Type] LIKE ('%Financial%') 
				AND RunningTotal > 0 
				THEN dbo.FN_GET_FINANCIAL_PENALTY ([Location ID],[Product Category],[Product Subcategory Enforcement],NULL,RunningTotal,RAND())
			ELSE [DGF Penalty] END [DGF Penalty]
		,[Notes]
		,[Tier_Pass_Through]
		,[Category Threshold Highlight]
		,[Category Threshold Alert]
		,[HP_Rep1]
		,[HP_Rep2]
		,[HP_Rep3]
		,[HP_Rep4]
		,[HP_Rep5]
		,[HP_Rep6]
		,[Email1]
		,[Email2]
		,[Email3]
		,[Email4]
		,[Email5]
		,[Email6]
		,[Selector]
		,[Matching Flag]
		,[G20 Sel/Cat Flag]
		,[Weekly Violation Selector]
		,[Fiscal Week Number]
		,[Validation Status New]
		,[RunningTotal]
		,ISNULL(u.UPC,'') AS UPC
		,a.Flag_Bundle
		,v.[Minimum Violation Date]
		,l.[Minimum Listing Date]
		,l.[Most Recent Listing Date]
		,r.[Date Requested]
		,CASE WHEN s.SKU IS NOT NULL THEN 1 ELSE 0 END [New SKU Flag]
		,[Top_Reseller_Flag]
		,c.MAX_Delivered_Date [Latest Courtesy Alert Date]
		,d.MAX_Delivered_Date_Product_Category AS [Product Category Latest Courtesy Alert Date]
		,Login_Type_ID
		,CASE WHEN ISNULL(Flag_StrikeThrough,0) = 1 THEN 'Strikethrough Pricing' ELSE 'Non-Strikethrough Pricing' END [Strikethrough Flag]
		,a.Violation_Type
INTO #output
FROM #output_prep3 a
LEFT JOIN #UPC_US u
	ON a.SKU = u.SKU
LEFT JOIN #MinViolationDate v ON a.[Location ID] = v.New_Location_ID
LEFT JOIN #Min_Max_Listing_Date l ON a.[Location ID] = l.Master_New_Location_Id
LEFT JOIN #DateRequested r ON a.[Location ID] = r.Master_New_Location_Id AND r.Ctry = 'US'
LEFT JOIN #NewSKU s ON a.SKU = s.SKU
LEFT JOIN #CourtesyAlerts c ON a.[Location ID] = c.New_Location_ID AND a.[Product Subcategory] = c.Alerts_Product_Type
LEFT JOIN #CourtesyAlertsProductCategory d ON a.[Location ID] = d.New_Location_ID AND a.[Product Category] = d.Product_Category_Reporting

CREATE NONCLUSTERED INDEX IX_output ON #output ([Country], [Week], [Location ID], [Product Subcategory], [Product Subcategory Enforcement]);

-------------------CANADA START------------------------

DROP TABLE IF EXISTS #ca_CTE_Adhoc --Adhoc visual inspections conducted Mondays: Prioritized due to inspecting all violations
SELECT fact.ID [Fact ID] 
	,fact.Data_Source_ID
	,a.[Week]
	,a.Collected_Date [Date]
	,a.[Product Category]
	,a.[Product Subcategory]
	,a.[Product Subcategory Enforcement]
	,a.SKU
	,UPPER(nm.[ASIN])[ASIN]
	,a.Product_Description
	,sel.Seller_Name_Unified [Account]
	,a.Seller_Name [Seller Name]
	,a.Master_New_Location_Id [Location ID]
	,rg.Penalty_Type [Seller Penalty Type]
	,a.Market [Market]
	,Login_Type [Log-in Type]
	,Price_Location_Unified [Price Location]
	,a.MAP
	,a.Seller_Advertised_Price [Advertised Price]
	,a.IR [Eligible IR]
	,a.LPP [Lowest Possible Price]
	,a.Screenshot_URL
	,ISNULL(a.[Validation Status],'Not Inspected') [Validation_Status_Raw]
	,a.Market_Unified_ID
	,ISNULL(rr.Reason_Description,a.Notes) [Notes]	--CH 6/13/19 Add for rejection reasons (Notes contains other notes, not solely rejection reasons)
	,Tier_Pass_Through
	,a.Master_SID
	,a.Flag_Bundle
	,CASE WHEN Login_Type = 'Free log-in' THEN 3 ELSE 1 END Login_Type_ID
	,ISNULL(fact.Flag_StrikeThrough,0) Flag_StrikeThrough
INTO #ca_CTE_Adhoc
FROM #DailyViolations_CA a
LEFT JOIN #Listings_CA fact
	ON	a.Fact_ID = fact.ID
LEFT JOIN HP_MAP_Canada._ref.Rejection_Reasons rr WITH(NOLOCK) 
	ON	a.Notes = CAST(rr.Reason_ID AS NVARCHAR)  -- LU 8/6/20 Added due to BG Team request to use Reason IDs instead of Notes in _temp table. 
LEFT JOIN HP_MAP_Canada._ref.Seller_Reporting_Group rg WITH(NOLOCK) 
	ON  rg.Master_SID = a.Master_SID
	AND rg.Product_Type = a.Product_Type_Indirect_MAP
	AND a.Collected_Date BETWEEN rg.Valid_From AND rg.Valid_To
LEFT JOIN	HP_MAP_Canada.[_final].[Seller_Pricing_NewMo_Canada] nm WITH(NOLOCK) 
	ON nm.ID = fact.NewMo_Source_Row_ID
LEFT JOIN   HP_MAP_Canada.[_final].[Dim_Seller] sel WITH(NOLOCK) 
	ON fact.Seller_ID = sel.Seller_ID

CREATE NONCLUSTERED INDEX IX_Ca_CTE_Adhoc_Location_ID_SKU_Week ON #ca_CTE_Adhoc([Location ID], SKU, [Week]);

DROP TABLE IF EXISTS #ca_CTE_Vtable --Violations from ViolationsMAP, not matching on Day/Sel/SKU
SELECT Fact_ID
	,Data_Source_ID
	,Week_Start_Date [Week]
	,Collected_Date [Date]
	,Product_Category_Reporting [Product Category]
	,CASE WHEN CSKU_Flag = 'C-SKU' THEN 'C-SKU'
		WHEN (Government_SKU_Flag = 'Government SKU' AND Product_Category_Reporting = 'Supplies') THEN 'G-SKU'
		WHEN Product_Line = '4X' THEN 'Scanjet'	-- Scanjet Inclusion
		ELSE Product_Type_Indirect_MAP_Dim_Product END  [Product Subcategory]
	,CASE WHEN Product_Type_Indirect_MAP_Dim_Product IN ('Ink','Toner') THEN 'Ink & Toner' 
	      WHEN Product_Type_Indirect_MAP_Dim_Product LIKE 'Large Format%' THEN 'Large Format'
		  ELSE Product_Type_Indirect_MAP_Dim_Product END [Product Subcategory Enforcement]
	,SKU
	,[ASIN]
	,Product_Description
	,Seller_Name_Unified [Account]
	,Seller_Name [Seller Name]
	,New_Location_ID [Location ID]
	,Seller_Penalty_Type [Seller Penalty Type]
	,Market_Unified [Market]
	,CASE WHEN ISNULL(a.Login_Type_ID, 1) = 3 THEN 'Free log-in' ELSE 'Public Site' END [Log-in Type]
	,Price_Location [Price Location]
	,MAP
	,Seller_Advertised_Price [Advertised Price]
	,Eligible_IR_Amount [Eligible IR]
	,Lowest_Possible_Price [Lowest Possible Price]
	,Screenshot_URL
	,ISNULL(Validation_Status,'Not Inspected') [Validation_Status_Raw] --if Adhoc already processed, then take away any other inspection results for week; Not Insp to get derived later on
	,CASE WHEN a.Market IN ('Websites Canada') 
					OR (a.Market = 'Amazon Canada' AND a.New_Location_ID = '10241372')
					OR (a.Market = 'Newegg Canada' AND a.New_Location_ID = '10248471')
					OR (a.Market = 'Walmart Canada' AND a.New_Location_ID = '10292113')
					THEN 1 
				WHEN a.Market = 'Amazon Canada' THEN 2
				WHEN a.Market = 'Walmart Canada' THEN 3
				WHEN a.Market = 'Ebay Canada' THEN 4
				WHEN a.Market = 'Newegg Canada' THEN 5 
				WHEN a.Market = 'Best Buy Canada' THEN 6 
				ELSE 7 END Market_Unified_ID
	,Reason_Description [Notes]--CH 6/13/19 Add for rejection reasons 
	,Tier_Pass_Through
	,Master_SID
	,a.Flag_Bundle
	,ISNULL(a.Login_Type_ID, 1) Login_Type_ID
	,Flag_StrikeThrough
	,Violation_Type
INTO #ca_CTE_Vtable
FROM (
	SELECT a.*
		,fact.Data_Source_ID
		,UPPER(nm.[ASIN])[ASIN]
		,ROW_NUMBER() OVER(
			PARTITION BY 
				a.New_Location_ID,a.Collected_Date, a.SKU, ISNULL(a.Login_Type_ID, 1) 
			ORDER BY 
				REPLACE(ISNULL(Validation_Status,'Z'),'Not Inspected','Z')
				, CASE 
					WHEN a.Market IN ('Websites Canada') 
						OR (a.Market = 'Amazon Canada' AND a.New_Location_Id = '10241372')
						OR (a.Market = 'Newegg Canada' AND a.New_Location_Id = '10248471')
						OR (a.Market = 'Walmart Canada' AND a.New_Location_Id = '10292113')
						THEN 1 
					WHEN a.Market = 'Amazon Canada' THEN 2
					WHEN a.Market = 'Walmart Canada' THEN 3
					WHEN a.Market = 'Ebay Canada' THEN 4
					WHEN a.Market = 'Newegg Canada' THEN 5 
					WHEN a.Market = 'Best Buy Canada' THEN 6 
					ELSE 7 
					END --when multiple markets, etc
				, Violation_Code --CH 7/16/21 adding to prioritize MAP, then CSKU, then QC; duplicate Fact IDs in ViolationsMAP due to moving QC under MAP
			) [Violation ID Selector] 
		,ISNULL(hpres.Reason_Description,res.Reason_Description) [Reason_Description] --CH 6/13/19 Add for rejection reasons -- LU/8/28/20 Add for HP Reasons froim Admin Tool - prioritizing over DSM Reason
	    ,ISNULL(fact.Flag_StrikeThrough,0) Flag_StrikeThrough
	FROM #Violations_CA a
	JOIN #Listings_CA fact on a.Fact_ID = fact.ID
	LEFT JOIN HP_MAP_Canada._ref.Rejection_Reasons res WITH(NOLOCK) 
		ON res.Reason_ID = a.Reason_ID
	LEFT JOIN HP_MAP_Canada._ref.HP_Rejection_Reasons hpres WITH(NOLOCK) 
		ON hpres.HP_Reason_ID = a.HP_Reason_ID
	LEFT JOIN HP_MAP_Canada._final.Seller_Pricing_NewMo_Canada nm WITH(NOLOCK) 
		ON nm.ID = fact.NewMo_Source_Row_ID
	WHERE a.Collected_Date < CAST(GETDATE() AS DATE)    -- 4/6/20 LU: due to intraday launch, need to restrict violations from current date
--		AND NOT (a.[Data_Source] = 'ACB' AND a.Product_Type_Reporting NOT IN ('Desktop','Notebook') AND a.Collected_Date > '2020-9-27')  -- 9/28/20 LU: ACB to stop providing SKU level non-PC violations. 
) a
WHERE [Violation ID Selector] = 1

CREATE NONCLUSTERED INDEX IX_Ca_CTE_Vtable_Location_ID_SKU_Week ON #ca_CTE_Vtable([Location ID], SKU, [Week]);

DROP TABLE IF EXISTS #ca_CTE_fact
SELECT	A.ID Fact_ID
	    ,a.Data_Source_ID
		,Week_Begin_Date_Alt [Week]
		,CAST(Collected_Date AS DATE) [Date]
		,[Product Category]
		,CASE WHEN CSKU_Flag = 'C-SKU' THEN 'C-SKU'
			    WHEN (Government_SKU_Flag = 'Government SKU' AND [Product Category] = 'Supplies') THEN 'G-SKU'
				WHEN Product_Line = '4X' THEN 'Scanjet'	-- Scanjet Inclusion
				ELSE [Product Subcategory] END [Product Subcategory]
		,CASE WHEN [Product Subcategory] IN ('Ink','Toner') THEN 'Ink & Toner' 
		      WHEN [Product Subcategory] LIKE 'Large Format%' THEN 'Large Format'
			  WHEN Product_Line = '4X' THEN 'Scanjet'	-- Scanjet Inclusion
		      ELSE [Product Subcategory] END [Product Subcategory Enforcement]
		,SKU
		,[ASIN]
		,Product_Description
		,Seller_Name_Unified Account
		,[Seller Name]
		,Master_New_Location_Id [Location ID]
		,Penalty_Type [Seller Penalty Type]
		,a.Market
		,Login_Type [Log-in Type]
		,Price_Location_Unified [Price Location]
		,MAP
		,Seller_Advertised_Price [Advertised Price]
		,IR [Eligible IR]
		,LPP [Lowest Possible Price]
		,Screenshot_URL
		,'Not Inspected' [Validation_Status_Raw]
		,[Market ID] Market_ID
		,CAST(NULL AS nvarchar) [Notes]--CH 6/13/19 Add for rejection reasons - fact won't have any
		,Tier_Pass_Through
		,Master_SID
		,a.Flag_Bundle
		,ISNULL(a.Login_Type_ID, 1) Login_Type_ID
		,Flag_StrikeThrough
INTO #ca_CTE_fact
FROM(
	SELECT fact.ID
		,fact.Data_Source_ID
		,fact.Seller_Advertised_Price
		,fact.MAP
		,fact.IR
		,fact.LPP
		,fact.Collected_Date
		,fact.Tier_Pass_Through
		,nm.[ASIN]
		,sel.Seller_Name_Unified
		,brs.Seller_Name [Seller Name]
		,sel.Master_New_Location_Id
		,sel.Master_SID
		,prdc.Product_Category_Reporting [Product Category]
		,prdc.Product_Type_Indirect_MAP [Product Subcategory]
		,prd.SKU
		,prd.CSKU_Flag
		,prd.Government_SKU_Flag
		,prd.Product_Description
		,prd.Product_Line	-- Scanjet Inclusion
		,dt.Week_Begin_Date_Alt
		,rg.Penalty_Type
		,mkt.Market_Unified  [Market]
		,lg.Login_Type
		,Price_Location_Unified
		,fact.Screenshot_URL
		,CASE WHEN mkt.Market IN ('Websites Canada') 
				OR smm.ID IS NOT NULL
				THEN 1 
			WHEN mkt.Market = 'Amazon Canada' THEN 2
			WHEN mkt.Market = 'Walmart Canada' THEN 3
			WHEN mkt.Market = 'eBay Canada' THEN 4
			WHEN mkt.Market = 'Newegg Canada' THEN 5
			WHEN mkt.Market = 'Best Buy Canada' THEN 6 
			ELSE 7 END [Market ID]
		,vc.ViolationCode [Violation_Code]
		,ROW_NUMBER() OVER(PARTITION BY sel.Master_New_Location_ID,CAST(fact.Collected_Date AS DATE), prd.SKU, ISNULL(fact.Login_Type_ID, 1) ORDER BY CASE WHEN mkt.Market IN ('Websites Canada') 
																											OR smm.ID IS NOT NULL
																											THEN 1 
																										WHEN mkt.Market = 'Amazon Canada' THEN 2
																										WHEN mkt.Market = 'Walmart Canada' THEN 3
																										WHEN mkt.Market = 'eBay Canada' THEN 4
																										WHEN mkt.Market = 'Newegg Canada' THEN 5
																										WHEN mkt.Market = 'Best Buy Canada' THEN 6 
																										ELSE 7 END--when multiple markets, et
																										,vc.ViolationCode
																										) [Violation ID Selector] 
		,fact.Flag_Bundle
		,ISNULL(fact.Login_Type_ID, 1) Login_Type_ID
		,ISNULL(fact.Flag_StrikeThrough,0) Flag_StrikeThrough
	FROM	#Listings_CA fact
	JOIN	HP_MAP_Canada._final.Dim_Date dt WITH(NOLOCK)						ON CAST(fact.Collected_Date as date) = dt.Full_Date		
	JOIN	HP_MAP_Canada._final.Dim_Seller sel WITH(NOLOCK)					ON fact.Seller_ID = sel.Seller_ID
	JOIN	HP_MAP_Canada._final.Dim_Product prd WITH(NOLOCK)					ON fact.Product_ID = prd.Product_ID
	JOIN	HP_MAP_Canada._final.Dim_Product prdc WITH(NOLOCK)					ON prd.SKU = prdc.SKU AND prdc.Flag_Current=1
	JOIN	HP_MAP_Canada._final.Dim_Price_Location loc WITH(NOLOCK)			ON fact.Price_Location_ID = loc.Price_Location_ID
	JOIN	HP_MAP_Canada._final.Dim_Product_Condition cond WITH(NOLOCK)		ON fact.Product_Condition_ID = cond.Product_Condition_ID
	JOIN	HP_MAP_Canada._final.Dim_Market mkt WITH(NOLOCK)					ON fact.Market_ID = mkt.Market_ID
	JOIN	HP_MAP_Canada._final.Dim_Login_Type lg WITH(NOLOCK)					ON fact.Login_Type_ID = lg.Login_Type_ID
	JOIN	HP_MAP_Canada._final.Seller_Pricing_NewMo_Canada nm WITH(NOLOCK)	ON fact.NewMo_Source_Row_ID = nm.ID
	LEFT JOIN HP_MAP_Canada._ref.Seller_Reporting_Group rg WITH(NOLOCK) 
		ON	rg.Master_SID = sel.Master_SID
		AND rg.Product_Type = prd.Product_Type_Indirect_MAP
		AND fact.Collected_Date >= rg.Valid_From 
		AND fact.Collected_Date < CASE WHEN rg.Valid_To = '9999-12-31' THEN rg.Valid_To ELSE DATEADD(D,1,rg.Valid_To) END
	LEFT JOIN HP_MAP_Canada._final.Bridge_Sellers brs WITH(NOLOCK)			ON fact.Seller_Name_ID = brs.Seller_Name_ID AND brs.Flag_Current = 1  -- 10/30/2020 LU added to include Seller Name detail
	LEFT JOIN HP_MAP_Canada._ref.Marketplace_Approved mpa WITH(NOLOCK)		
		ON	mpa.New_Location_ID = brs.Master_New_Location_Id --CH 7/16/21: adding new marketplace tables to bring in QC
		AND mpa.Market_Unified = mkt.Market_Unified
		AND CAST(Fact.Collected_Date AS date) BETWEEN mpa.Valid_From AND mpa.Valid_To
		AND mpa.Country = 'Canada'
		AND mpa.Flag_Active = 1
	LEFT JOIN HP_MAP_Canada._ref.Seller_Market_Mapping smm WITH(NOLOCK) 
		ON	brs.Seller_Name_Unified = smm.Seller_Name_Unified			--CH 7/16/21: adding new marketplace tables to bring in QC											
		AND mkt.Market_Unified = smm.Market_Unified
	CROSS APPLY HP_MAP_Canada.dbo.TVF_GET_VIOLATION_CODE_EPC(
		fact.Seller_Advertised_Price,
		fact.IR,
		fact.MAP,
		fact.PC,
		prd.CSKU_Flag,
		fact.Tier_Pass_Through,
		prd.Product_Category_Reporting,
		fact.Flag_Bundle,
		fact.Strikethrough_Price,
		fact.Coupon_Discount_Price
	) AS vc	-- New FN
	WHERE (--adding scope for both MAP and QC
			(
			( prd.In_MAP_Scope_Flag = 'In MAP Scope' OR (prd.CSKU_Flag = 'C-SKU' OR (prd.Government_SKU_Flag = 'Government SKU' AND prd.Product_Category_Reporting = 'Supplies'))) --fact for Canada C-SKUs only
			AND loc.In_MAP_Scope_Flag = 'In MAP Scope'
			AND mkt.In_MAP_Scope_Flag = 'In MAP Scope'
			AND lg.In_MAP_Scope = 'In MAP Scope'
			AND (vc.ViolationCode IS NOT NULL OR (prd.CSKU_Flag = 'C-SKU' OR (prd.Government_SKU_Flag = 'Government SKU' AND prd.Product_Category_Reporting = 'Supplies'))))
		)
			AND NOT EXISTS(SELECT * 
							FROM #ca_CTE_Vtable v  WITH(NOLOCK) 
							WHERE fact.Collected_Date >= v.[Date]
									AND fact.Collected_Date < DATEADD(D,1,v.[Date])
									AND v.[Location ID] = sel.Master_New_Location_Id	--CH 11/4/19 added to account for HP; not in ViolationsMAP
									AND v.SKU = prd.SKU) --added detail on SKU to account for LF/LFS not in ViolMAP for Dir/VPA; 9/22 these have been added
			AND NOT EXISTS(SELECT * 
							FROM #ca_CTE_Adhoc ad  WITH(NOLOCK) 
							WHERE ad.[Location ID] = sel.Master_New_Location_Id 
									AND ad.SKU = prd.SKU 
									AND fact.Collected_Date >= ad.[Date]
									AND fact.Collected_Date < DATEADD(D,1,ad.[Date]))
			--AND fact.Quantity = 1
	) a
WHERE [Violation ID Selector] = 1

CREATE NONCLUSTERED INDEX IX_Ca_CTE_Fact_Location_ID_SKU_Week ON #ca_CTE_fact([Location ID], SKU, [Week]);

DROP TABLE IF EXISTS #ca_CTE_Status  --grabbing active status
SELECT DISTINCT a.[ID]
	,a.[Notification_ID]
	,a.[Seller Name]
	,a.[New Location ID]
	,a.[Group]
	,a.[Product Line]
	,a.[Product_Type]
	,a.[Supplies Qualification]
	,a.[Print_Qualification]
	,a.[Notification_Approval_Status]
	,a.[Letter Sent Date]
	,a.[Letter Delivered Date]
	,a.[Letter Tracking Num]
	,a.[Letter Type]
	,a.[Comments]
	,a.[Buffer Period Start]
	,a.[Buffer Period End]
	,a.[Penalty Period Start]
	,a.[Penalty Period End]
	,a.[Product Suspension Start]
	,a.[Product Suspension End]
	,a.[MAP Status]
	,a.[MAP Status Detail]
	,a.[Rehab Flag]
	,a.[Annual Revenue]
	,a.[60-day Product Suspension Impact]
	,a.[180-day Product Suspension Impact]
	,a.[Product Suspension Impact]
	,a.[DGF Penalty]
	,a.[Account Owner]
	,a.[Active Flag]
	,a.[Repeat Offender Flag]
	,a.[Contact Channel]
	,a.[Program]
	,a.[Marketplace Suspension Flag]
	,a.[MPA Letter Delivered Date]
	,a.[Country]
	,a.[Restricted SKU Enforcement]
	,a.[Seller Reporting Group]
	,a.[Notification Generation Date]
	,a.[Product Line_QDN Tool]
	,b.Product_Category
	,CASE WHEN a.Product_Type = 'Large Format Supplies' THEN a.Product_Type ELSE b.Product_Subcategory END Product_Subcategory
INTO #ca_CTE_Status
FROM _report.VI_MAP_QC_Status_Canada a WITH (NOLOCK)
LEFT JOIN #Product_Category b ON CASE WHEN b.Product_Category LIKE '%Supplies' THEN 'Ink & Toner'
                                      WHEN b.Product_Subcategory LIKE '%Large Format' THEN 'Large Format'
									  ELSE b.Product_Subcategory END = CASE WHEN a.[Product Line] = 'HPS Printers' THEN 'Inkjet'
									                                        WHEN a.[Product Line] = 'OPS Printers' THEN 'LaserJet'
																			WHEN a.[Product Line] = 'Toner' THEN 'Ink & Toner'
																			ELSE a.[Product Line] END
WHERE a.Program = 'MAP'
	 AND a.Notification_ID IS NOT NULL
	 AND a.[Active Flag] = 'Active'
	 AND a.[Letter Type] <> 'Courtesy Alert'

CREATE NONCLUSTERED INDEX IX_Ca_CTE_Status ON #ca_CTE_Status ([New Location ID], [Product_Subcategory]);


DROP TABLE IF EXISTS #ca_CTE_Union  --combining each of the three, then applying derived VI results
SELECT CASE WHEN [Validation_Status_Raw] = 'Not Inspected'
			THEN CASE WHEN MAX(CASE WHEN [Validation_Status_Raw] = 'Accepted' THEN 1 ELSE 0 END) OVER(PARTITION BY [Week],[Location ID],SKU,ISNULL(Login_Type_ID, 1)) = 1 THEN 'Accepted - Derived'
					WHEN MAX(CASE WHEN [Validation_Status_Raw] = 'Rejected' THEN 1 ELSE 0 END) OVER(PARTITION BY [Week],[Location ID],SKU,ISNULL(Login_Type_ID, 1)) = 1 THEN 'Rejected - Derived' 
					ELSE Validation_Status_Raw END
		ELSE [Validation_Status_Raw]
		END [Validation Status]
	,CASE WHEN MAX(CASE WHEN [Validation_Status_Raw] = 'Accepted' THEN 1 ELSE 0 END) OVER(PARTITION BY [Week],[Location ID],SKU) = 1 THEN 'Accepted'
					WHEN MAX(CASE WHEN [Validation_Status_Raw] = 'Rejected' THEN 1 ELSE 0 END) OVER(PARTITION BY [Week],[Location ID],SKU) = 1 THEN 'Rejected' 
					ELSE Validation_Status_Raw END [Validation Status Weekly]
	,a.*
INTO #ca_CTE_Union
FROM (
	SELECT *
		,'N/A' AS Violation_Type
		,DENSE_RANK() OVER(ORDER BY Week DESC) [Adhoc Week Selector]
	FROM #ca_CTE_Adhoc WITH(NOLOCK) 

	UNION 
		
	SELECT * 
		,0 [Adhoc Week Selector]
	FROM #ca_CTE_Vtable WITH(NOLOCK) 

	UNION 

	SELECT *
		,'N/A' AS Violation_Type
		,-1 
	FROM #ca_CTE_Fact WITH(NOLOCK)
) a

CREATE NONCLUSTERED INDEX IX_Ca_CTE_Union ON #ca_CTE_Union (Master_SID, [Date], [Product Subcategory]);

DROP TABLE IF EXISTS #ca_CTE_cj
SELECT DISTINCT a.*
	,b.*
	,c.* 
	,CASE WHEN rg.Penalty_Type IS NULL AND b.[Product Category] IN ('Supplies', 'CPS','BPS') AND b.[Product Subcategory] <> 'Large Format Supplies' THEN '30, 60, 90 Suspension'
	      WHEN rg.Penalty_Type IS NULL AND (b.[Product Category] = 'Print' OR b.[Product Subcategory] = 'Large Format Supplies') THEN '14, 30, 60 Suspension'
	      ELSE rg.Penalty_Type END [Seller Penalty Type]
	,ISNULL(rg.Reporting_Group,'Group B') [Reporting Group]   
INTO #ca_CTE_cj
FROM #Weeks a
CROSS APPLY (
	SELECT DISTINCT Product_Category_Reporting [Product Category]
		,Product_Type_Indirect_MAP [Product Subcategory]
	FROM HP_MAP_Canada._final.Dim_Product p WITH(NOLOCK) --switching to Dim since LF,PW,SJ will not come through if no violations
	WHERE ((p.Product_Category_Reporting IN ('Print','Supplies','CPS','BPS')
				AND (p.In_MAP_Scope_Flag = 'In MAP Scope' OR p.Product_Line = '4X')) -- Scanjet Inclusion
				AND p.Flag_Current=1)
	UNION
	SELECT 'Supplies' AS [Product Category], --DP 10/19/22 adding C-SKU to cj to separate restricted ink/toner
	'C-SKU' AS [Product Subcategory]
	UNION
	SELECT 'Supplies' AS [Product Category],
	'G-SKU' AS [Product Subcategory]
)b
CROSS APPLY 
(
	SELECT DISTINCT
	[Account]
	,ISNULL(sft.Storefront_Names,'Seller not Marketplace Approved') [Storefront Name(s)]    -- 3/20 LU added for Storefront Name(s)
	,[Location ID]
	,Master_SID
	FROM #ca_CTE_Union c WITH(NOLOCK) --pulling only g20 sellers?
	LEFT JOIN [HP_MAP_Prod]._ref.Marketplace_Approved sft WITH (NOLOCK) ON c.[Location ID] = sft.New_Location_ID  AND sft.Country = 'Canada'  
)c
LEFT JOIN HP_MAP_Canada._ref.Seller_Reporting_Group rg WITH(NOLOCK) ON rg.Master_SID = c.Master_SID
	AND a.Date BETWEEN rg.Valid_From AND rg.Valid_To
	AND rg.Product_Type = CASE WHEN b.[Product Subcategory] IN ('C-SKU','G-SKU') THEN 'Toner' ELSE b.[Product Subcategory] END

CREATE NONCLUSTERED INDEX IX_Ca_CTE_cj ON #ca_CTE_cj (Master_SID, [Date], [Product Subcategory], [Location ID]);

-- Pulling Canada Contacts for report tooltip & covered/uncovered split
DROP TABLE IF EXISTS #ca_CTE_Contacts
SELECT DISTINCT a.Account [Seller Name Unified]
	,a.[Location ID] [New Location ID]
	,a.[Product Category]
	,rep1.Rep AS HP_Rep1
	,rep2.Rep AS HP_Rep2
	,rep3.Rep AS HP_Rep3
	,rep4.Rep AS HP_Rep4
	,rep5.Rep AS HP_Rep5
	,rep6.Rep AS HP_Rep6
	,LOWER(i.HP_Rep_1_Email) AS Email1
	,LOWER(i.HP_Rep_2_Email) AS Email2
	,LOWER(i.HP_Rep_3_Email) AS Email3
	,LOWER(i.HP_Rep_4_Email) AS Email4
	,LOWER(i.HP_Rep_5_Email) AS Email5
	,LOWER(i.HP_Rep_6_Email) AS Email6
INTO #ca_CTE_Contacts
FROM (SELECT DISTINCT [Location ID]
                      ,Account
					  ,CASE WHEN [Product Subcategory] LIKE 'Large Format%' THEN 'Large Format'
							ELSE [Product Category] END [Product Category]
					  ,[Product Subcategory] 
      FROM #ca_CTE_cj) a
LEFT JOIN HP_MAP_Canada.dbo.VI_SELLERS_EMAIL_INFO_ALL i WITH(NOLOCK) 
	ON 
		i.New_Location_ID = a.[Location ID]
	AND i.Product_Category = CASE WHEN a.[Product Category] IN ('CPS','BPS') THEN 'PC' ELSE a.[Product Category] END
	AND i.Source_Rank = 1
LEFT JOIN _report.Seller_Email_Union rep1 WITH(NOLOCK) ON i.HP_Rep_1_Email = rep1.Email
LEFT JOIN _report.Seller_Email_Union rep2 WITH(NOLOCK) ON i.HP_Rep_2_Email = rep2.Email
LEFT JOIN _report.Seller_Email_Union rep3 WITH(NOLOCK) ON i.HP_Rep_3_Email = rep3.Email
LEFT JOIN _report.Seller_Email_Union rep4 WITH(NOLOCK) ON i.HP_Rep_4_Email = rep4.Email
LEFT JOIN _report.Seller_Email_Union rep5 WITH(NOLOCK) ON i.HP_Rep_5_Email = rep5.Email
LEFT JOIN _report.Seller_Email_Union rep6 WITH(NOLOCK) ON i.HP_Rep_6_Email = rep6.Email

CREATE NONCLUSTERED INDEX IX_Ca_CTE_Contacts ON #ca_CTE_Contacts ([New Location ID], [Product Category]);

-- OUTPUT (all G20 sellers + nonG20 for just CSKUs)
DROP TABLE IF EXISTS #ca_output_prep
SELECT DISTINCT 'Canada' [Country]
	,a.* 
,CASE WHEN g20.Seller_Name_Unified IS NOT NULL THEN 1 		
	ELSE 0 END [G20 Sel/Cat Flag]
,ROW_NUMBER() OVER(PARTITION BY a.[Location ID],a.Week, ISNULL(a.SKU,[Product Subcategory]),Login_Type_ID ORDER BY REPLACE(ISNULL([Validation Status],'Z'),'Not Inspected','Z')) [Weekly Violation Selector]  -- 9/17/2020 LU: Moved up a line, certain weeks weren't getting a WVS of 1
,Fiscal_Week_Number [Fiscal Week Number]
INTO #ca_output_prep	
FROM
(
	SELECT a.*
		, ROW_NUMBER() OVER(PARTITION BY a.[Location ID],a.Date, ISNULL(a.SKU,[Product Subcategory]),Login_Type_ID ORDER BY [Letter Type] DESC) [Selector]
		, 0 [Matching Flag]
	FROM 
	(
		SELECT DISTINCT [Validation Status]
			, [Validation Status Weekly]
			, a.[Week]
			, a.[Date]
			, a.[Product Category]
			, a.[Product Subcategory]
			, d.[Product Subcategory Enforcement]
			, [Fact ID]
			, Data_Source_ID
			, d.SKU
			, d.[ASIN]
			, d.Product_Description
			, a.Account [Account]
			, d.[Seller Name]
			, [Storefront Name(s)]  -- 3/20 LU Adding StoreFront Name(s)
			, a.[Location ID]
			,CASE WHEN qpp.Account IS NOT NULL THEN dbo.FN_GET_SELLER_STATUS (a.[Product Category], sel.Supplies_Qualification, sel.Print_Qualification,sel.Qualified_Business_Personal_Systems,sel.Qualified_Consumer_Personal_Systems) 
				ELSE 'Unauthorized' END Seller_Status
	        ,CASE WHEN qpp.[Status] = 'Dropped' THEN qpp.Drop_Date  
	              WHEN qpp.Action_Required = 'PA Termination' THEN qpp.Expiration_Date
		          ELSE NULL END [Termination Date]
			, a.[Seller Penalty Type]
			, a.[Reporting Group]   -- 3/6 LU Added for MPA Reporting Group
			, [Market]
			, [Log-in Type]
			, [Price Location]
			, MAP
			, [Advertised Price]
			, [Eligible IR]
			, [Lowest Possible Price]
			, [Validation_Status_Raw]
			, e.[Letter Type]
			, CAST(ISNULL(e.[MAP Status Detail],'N/A') AS NVARCHAR(MAX)) [MAP Status Detail]
			, e.[Letter Delivered Date]
			, e.[Notification Generation Date]
			, e.[Buffer Period Start]
			, e.[Buffer Period End]
			, e.[Product Suspension Start]
			, e.[Product Suspension End]
			, e.[Penalty Period Start]
			, e.[Penalty Period End]
			, Screenshot_URL
			, e.[DGF Penalty]
			, Notes
			,d.Tier_Pass_Through
			,CASE WHEN a.[Location ID] = '99999999' THEN 1 ELSE Threshold_Action END [Category Threshold Highlight]  -- Want to apply a threshold of 1 for HP
			,CASE WHEN a.[Location ID] = '99999999' THEN 1 ELSE Threshold_Action END [Category Threshold Alert]
			,HP_Rep1
			,HP_Rep2
			,HP_Rep3
			,HP_Rep4
			,HP_Rep5
			,HP_Rep6
			,gc.Email1
			,gc.Email2
			,gc.Email3
			,gc.Email4
			,gc.Email5
			,gc.Email6
			,d.Flag_Bundle
			,ISNULL(d.Login_Type_ID, 1) Login_Type_ID
			,ISNULL(d.Flag_StrikeThrough,0) Flag_StrikeThrough
			,d.Violation_Type
		FROM #ca_CTE_cj a WITH(NOLOCK) 
		LEFT JOIN #ca_CTE_Union d WITH(NOLOCK) ON d.Master_SID = a.Master_SID
				AND d.[Product Subcategory] = a.[Product Subcategory] 
				AND d.Date = a.Date
        LEFT JOIN #ca_CTE_Status e ON e.[New Location ID] = a.[Location ID] 
		                AND CASE WHEN a.[Product Subcategory] = 'Large Format Supplies' THEN 'Large Format' ELSE a.[Product Subcategory] END = CASE WHEN e.[Product_Subcategory] = 'Large Format Supplies' THEN 'Large Format'  ELSE e.[Product_Subcategory] END
		LEFT JOIN HP_MAP_Canada._final.Dim_Seller sel WITH(NOLOCK) ON a.[Location ID] = sel.Master_New_Location_Id AND sel.Flag_Current = 1
		LEFT JOIN HP_MAP_Canada._ref.Violation_Rules vr WITH(NOLOCK) ON vr.Program = 'MAP'
		                                    AND a.[Reporting Group] = vr.Seller_Group
											AND a.[Seller Penalty Type] = vr.Penalty_Description
											AND CASE WHEN a.[Product Subcategory] IN ('C-SKU','G-SKU') THEN 'Toner' ELSE a.[Product Subcategory] END = CASE WHEN vr.Product_Type_Hybrid = 'HPS Printers' THEN 'Inkjet' WHEN vr.Product_Type_Hybrid = 'OPS Printers' THEN 'LaserJet' ELSE vr.Product_Type_Hybrid END
											AND CASE WHEN e.[Letter Type] IS NULL THEN 'V1' 
													 WHEN a.[Seller Penalty Type] NOT LIKE '%Financial%' AND e.[Letter Type] = 'V1' THEN 'V2'
													 WHEN a.[Seller Penalty Type] NOT LIKE '%Financial%' AND e.[Letter Type] = 'V2' THEN 'V3'  
													 WHEN a.[Seller Penalty Type] NOT LIKE '%Financial%' AND e.[Letter Type] = 'V3' THEN 'V4'	 
												     WHEN a.[Seller Penalty Type] NOT LIKE '%Financial%' AND e.[Letter Type] IN ('V4','V5') THEN 'V5'
													 ELSE e.[Letter Type] END = vr.[Action]
											AND a.[Date] BETWEEN vr.Valid_From AND vr.Valid_To
		LEFT JOIN #ca_CTE_Contacts gc ON a.[Location ID] = gc.[New Location ID]  -- 9/10/20 LU added for G20 Contacts
							AND CASE WHEN a.[Product Subcategory] LIKE 'Large Format%' THEN 'Large Format'
									WHEN a.[Product Subcategory] IN ('C-SKU','G-SKU') THEN 'Supplies'
									ELSE a.[Product Category] END = gc.[Product Category]	
			LEFT JOIN HP_QPP_Prod._web.tbl_Partner qpp WITH (NOLOCK) 
				ON	qpp.HPI_Location_ID = sel.Master_New_Location_Id 
				AND qpp.Flag_Active = 1 
				AND qpp.Flag_Current = 1
				AND qpp.[Status] = 'Active'	
				AND qpp.Country IN ('CA', 'Canada')
		WHERE a.[Location ID] <> 'N/A'
	) a
) a
LEFT JOIN HP_MAP_Canada._ref.G20_Seller_Product g20 WITH(NOLOCK) ON g20.Master_New_Location_Id = a.[Location ID]
	AND g20.Product_Type_Indirect_MAP = CASE WHEN a.[Product Subcategory] IN ('C-SKU', 'G-SKU') THEN 'Toner' ELSE a.[Product Subcategory] END
	AND g20.Valid_To = '9999-12-31' -- don't have flag current for table
LEFT JOIN #Fiscal_Week fw ON a.[Week] = fw.Week_Begin_Date_Alt
WHERE Selector = 1

CREATE NONCLUSTERED INDEX IX_Ca_output_prep ON #ca_output_prep ([Location ID], [Week], [Product Subcategory]);

DROP TABLE IF EXISTS #ca_live_link
SELECT a.[Fact ID]
       ,ISNULL(c.Listing_URL,'N/A') [Listing URL]
INTO #ca_live_link
FROM #ca_output_prep  a
LEFT JOIN HP_MAP_Canada._final.Fact_Listings b WITH (NOLOCK) ON a.[Fact ID] = b.ID
LEFT JOIN HP_MAP_Canada._final.Seller_Pricing_NewMo_Canada c WITH (NOLOCK) ON c.ID = b.NewMo_Source_Row_ID
WHERE ISNULL(a.Screenshot_URL, 'N/A') = 'N/A'

DROP TABLE IF EXISTS #ca_output_prep2
SELECT [Country]
	,a.[Validation Status]
	,a.[Validation Status Weekly]
	,a.[Week]
	,a.[Date]
	,a.[Product Category]
	,a.[Product Subcategory]
	,a.[Product Subcategory Enforcement]
	,a.[Fact ID]
	,a.Data_Source_ID [Data Source ID]
	,a.[SKU]
	,a.[ASIN]
	,a.[Product_Description]
	,a.[Account]
	,a.[Seller Name]
	,a.[Storefront Name(s)]
	,a.[Location ID]
	,a.Seller_Status [Seller Status]
	,a.[Termination Date]
	,a.[Seller Penalty Type]
	,a.[Reporting Group]
	,a.[Market]
	,a.[Log-in Type]
	,a.[Price Location]
	,a.[MAP]
	,a.[Advertised Price]
	,a.[Eligible IR]
	,a.[Lowest Possible Price]
	,a.[Validation_Status_Raw]
	,a.[Letter Type]
	,a.[MAP Status Detail]
	,b.[Letter Delivered Date]
	,b.[Notification Generation Date]
	,b.[Buffer Period Start]
	,b.[Buffer Period End]
	,b.[Product Suspension Start]
	,b.[Product Suspension End]
	,b.[Penalty Period Start]
	,b.[Penalty Period End]
	,CASE WHEN ISNULL(a.[Screenshot_URL], 'N/A') = 'N/A' THEN c.[Listing URL] ELSE a.[Screenshot_URL] END [Screenshot_URL]
	,a.[DGF Penalty]
	,a.[Notes]
	,a.[Tier_Pass_Through]
,CASE WHEN a.[Category Threshold Highlight] IS NULL AND a.[Seller Penalty Type] LIKE '%Financial' AND a.[Product Subcategory Enforcement] = 'Ink & Toner' THEN 10
	    WHEN a.[Category Threshold Highlight] IS NULL AND a.[Seller Penalty Type] NOT LIKE '%Financial' AND a.[Product Subcategory Enforcement] = 'Ink & Toner' THEN 5
		WHEN a.[Category Threshold Highlight] IS NULL AND a.[Product Subcategory Enforcement] IN ('Inkjet','LaserJet','Large Format','Large Format Supplies') THEN 2
		ELSE a.[Category Threshold Highlight] END [Category Threshold Highlight]
,CASE WHEN a.[Category Threshold Alert] IS NULL AND a.[Seller Penalty Type] LIKE '%Financial' AND a.[Product Subcategory Enforcement] = 'Ink & Toner' THEN 10
	    WHEN a.[Category Threshold Highlight] IS NULL AND a.[Seller Penalty Type] NOT LIKE '%Financial' AND a.[Product Subcategory Enforcement] = 'Ink & Toner' THEN 5
		WHEN a.[Category Threshold Alert] IS NULL AND a.[Product Subcategory Enforcement] IN ('Inkjet','LaserJet','Large Format','Large Format Supplies') THEN 2
		ELSE a.[Category Threshold Alert] END [Category Threshold Alert]
	,a.HP_Rep1
	,a.HP_Rep2
	,a.HP_Rep3
	,a.HP_Rep4
	,a.HP_Rep5
	,a.HP_Rep6
	,a.[Email1]
	,a.[Email2]
	,a.[Email3]
	,a.[Email4]
	,a.[Email5]
	,a.[Email6]
	,a.[Selector]
	,a.[Matching Flag]
	,a.[G20 Sel/Cat Flag]
	,a.[Weekly Violation Selector]
	,a.[Fiscal Week Number]
	,CASE WHEN [Validation Status] LIKE 'Accepted%' AND [MAP Status Detail] NOT LIKE '%To be Sent' AND a.Date > ISNULL(b.[Buffer Period End],'1999-01-01') THEN 'Accepted - Contributing to Threshold'
		    WHEN [Validation Status] LIKE 'Accepted%' AND (a.Date <= ISNULL(b.[Buffer Period End],'1999-01-01') OR [MAP Status Detail] LIKE '%To be Sent') THEN 'Accepted - Not Contributing to Threshold'
			ELSE [Validation Status] END [Validation Status New]  -- 04/28/23 ED: Adding 'Validation Status New' to diferentiate between accepted violations contr. to threshold vs not contr. to threshold
	,a.Flag_Bundle
	,CASE WHEN t.Master_New_Location_Id IS NOT NULL THEN 1 ELSE 0 END [Top_Reseller_Flag]
	,a.Login_Type_ID
    ,CASE WHEN ISNULL(a.Flag_StrikeThrough,0) = 1 THEN 'Strikethrough Pricing' ELSE 'Non-Strikethrough Pricing' END [Strikethrough Flag]
	,a.Violation_Type
INTO #ca_output_prep2
FROM #ca_output_prep a
LEFT JOIN (SELECT DISTINCT [Week]             
	                        ,[Product Subcategory]
							,[Account]
							,[Location ID]
							,[Letter Delivered Date]
							,[Notification Generation Date]
							,[Buffer Period Start]
						   	,[Buffer Period End]
							,[Product Suspension Start]
							,[Product Suspension End]
							,[Penalty Period Start]
							,[Penalty Period End]
			FROM #ca_output_prep
			WHERE [Letter Delivered Date] IS NOT NULL) b ON a.[Location ID] = b.[Location ID]
			                                                AND a.[Week] = b.[Week]
															AND a.[Product Subcategory] = b.[Product Subcategory]
LEFT JOIN #ca_live_link c ON a.[Fact ID] = c.[Fact ID]  
LEFT JOIN [HP_MAP_Canada]._ref.Courtesy_Alerts_Top_Seller_List t WITH (NOLOCK) ON t.Master_New_Location_Id = a.[Location ID]
	WHERE NOT (ISNULL(Data_Source_ID,100) = 9 AND (Seller_Status = 'Qualified' OR Seller_Status = 'Not Qualified'))   
	    AND NOT ([Date] < '2023-11-01' AND ISNULL(Data_Source_ID,100) = 11)

CREATE NONCLUSTERED INDEX IX_Ca_output_prep2 ON #ca_output_prep2 ([Week], [Location ID], [Product Subcategory Enforcement], [Date]);

DROP TABLE IF EXISTS #ca_output
SELECT a.*
	,SUM(CASE WHEN b.SKU IS NOT NULL THEN 1 ELSE 0 END) OVER ( PARTITION BY a.[Week], a.[Location ID], a.[Product Subcategory Enforcement] ORDER BY a.[Date] ) AS RunningTotal
	,ISNULL(u.UPC,'') AS UPC
	,v.[Minimum Violation Date]
	,l.[Minimum Listing Date]
	,l.[Most Recent Listing Date]
	,r.[Date Requested]
	,CASE WHEN s.SKU IS NOT NULL THEN 1 ELSE 0 END [New SKU FLag]
	,c.MAX_Delivered_Date [Latest Courtesy Alert Date]
	,d.MAX_Delivered_Date_Product_Category AS [Product Category Latest Courtesy Alert Date]
INTO #ca_output
FROM #ca_output_prep2 a
LEFT JOIN (
		SELECT DISTINCT Week, MIN(Date) Min_Date, [Location ID], SKU
		FROM #ca_output_prep2
		WHERE SKU IS NOT NULL
		GROUP BY Week, [Location ID], SKU
) b
	ON a.Week = b.Week 
	AND a.Date = b.Min_Date
	AND a.[Location ID] = b.[Location ID]
	AND a.SKU = b.SKU
LEFT JOIN #UPC_CAN u
	ON a.SKU = u.SKU
LEFT JOIN #MinViolationDate_CA v ON a.[Location ID] = v.New_Location_ID
LEFT JOIN #Min_Max_Listing_Date_CA l ON a.[Location ID] = l.Master_New_Location_Id
LEFT JOIN #DateRequested r ON a.[Location ID] = r.Master_New_Location_Id AND r.Ctry = 'Canada'
LEFT JOIN #NewSKU_CA s ON a.SKU = s.SKU
LEFT JOIN #CourtesyAlerts_CA c ON a.[Location ID] = c.New_Location_ID AND a.[Product Subcategory] = c.Alerts_Product_Type
LEFT JOIN #CourtesyAlertsProductCategory_CA d ON a.[Location ID] = d.New_Location_ID AND a.[Product Category] = d.Product_Category_Reporting

CREATE NONCLUSTERED INDEX IX_ca_output ON #ca_output ([Country], [Week], [Location ID], [Product Subcategory]);

-------------------CANADA END--------------------------

-- FINAL OUTPUT PREP --
DROP TABLE IF EXISTS #final_prep
SELECT 
	 Country	
	,[Validation Status]
	,[Validation Status Weekly]	
	,a.[Fiscal Week Number]
	,a.[Week]
	,a.[Date]
	,[Product Category]
	,[Product Subcategory]	
	,CASE WHEN [Product Category] = 'Large Format' THEN [Product Category]
	      WHEN [Product Category] IN ('PS','Print') THEN [Product Subcategory]
	      WHEN [Product Category] LIKE '%Supplies' THEN 'Ink & Toner' END [Product Subcategory Enforcement] 
	,[Fact ID]
	,a.[SKU]
	,[ASIN]
	,[Product_Description]
	,CASE WHEN Country = 'US' AND a.[Location ID] = '10267108' THEN 'Office Products Center Inc' ELSE a.[Account] END [Account]
	,[Seller Name]	
	,[Storefront Name(s)]
	,a.[Location ID]	
	,[Seller Status]
	,[Termination Date]
	,[Seller Penalty Type]
	,[Reporting Group]
	,[Market]
	,[Log-in Type]
	,[Price Location]
	,[MAP]
	,[Advertised Price]
	,[Eligible IR]
	,[Lowest Possible Price]
	,[Validation_Status_Raw]
	,[Letter Type]
	,[MAP Status Detail]
	,[Letter Delivered Date]
	,[Notification Generation Date]
	,[Buffer Period Start]
	,[Buffer Period End]
	,[Product Suspension Start]
	,[Product Suspension End]
	,[Penalty Period Start]
	,[Penalty Period End]
	,[Screenshot_URL]
	,[DGF Penalty]
	,a.[Notes]
	,Tier_Pass_Through
	,[Category Threshold Highlight]
	,[Category Threshold Alert]
	,[HP_Rep1]
	,[HP_Rep2]
	,[HP_Rep3]
	,[HP_Rep4]
	,[HP_Rep5]
	,[HP_Rep6]
	,[Email1]
	,[Email2]
	,[Email3]
	,[Email4]
	,[Email5]
	,[Email6]
	,[Selector]
	,[Matching Flag]
	,[G20 Sel/Cat Flag]
	,[Weekly Violation Selector]
	,[Validation Status New]
	,RunningTotal
	,MAX([UPC]) [UPC]
	,ISNULL(a.Flag_Bundle,0) [Bundle Flag]
	,[Minimum Violation Date]
	,[Minimum Listing Date]
	,[Most Recent Listing Date]
	,MIN([Date Requested]) [Date Requested]
	,[New SKU Flag]
	,[Top_Reseller_Flag]
	,MAX([Latest Courtesy Alert Date]) [Latest Courtesy Alert Date]
	,MAX([Product Category Latest Courtesy Alert Date]) [Product Category Latest Courtesy Alert Date]
	,Login_Type_ID
	,[Strikethrough Flag]
	,Violation_Type
INTO #final_prep
FROM (
	SELECT
		Country	
	   ,[Validation Status]
	   ,[Validation Status Weekly]	
	   ,[Fiscal Week Number]
	   ,[Week]
	   ,[Date]
	   ,b.Product_Category as [Product Category]
	   ,[Product Subcategory]	
	   ,[Product Subcategory Enforcement]
	   ,[Fact ID]
	   ,[SKU]
	   ,[ASIN]
	   ,[Product_Description]
	   ,[Account]	
	   ,[Seller Name]	
	   ,[Storefront Name(s)]
	   ,[Location ID]	
	   ,CASE WHEN [Location ID] = '99999999' THEN 'Qualified' ELSE [Seller Status] END [Seller Status]
	   ,[Termination Date]
	   ,[Seller Penalty Type]
	   ,[Reporting Group]
	   ,[Market]
	   ,[Log-in Type]
	   ,[Price Location]
	   ,[MAP]
	   ,[Advertised Price]
	   ,[Eligible IR]
	   ,[Lowest Possible Price]
	   ,[Validation_Status_Raw]
	   ,[Letter Type]
	   ,[MAP Status Detail]
	   ,[Letter Delivered Date]
	   ,[Notification Generation Date]
	   ,[Buffer Period Start]
	   ,[Buffer Period End]
	   ,[Product Suspension Start]
	   ,[Product Suspension End]
	   ,[Penalty Period Start]
	   ,[Penalty Period End]
	   ,[Screenshot_URL]
	   ,[DGF Penalty]
	   ,[Notes]
	   ,[Tier_Pass_Through]
	   ,[Category Threshold Highlight]
	   ,[Category Threshold Alert]
       ,[HP_Rep1]
       ,[HP_Rep2]
       ,[HP_Rep3]
       ,[HP_Rep4]
       ,[HP_Rep5]
       ,[HP_Rep6]
	   ,[Email1]
	   ,[Email2]
	   ,[Email3]
	   ,[Email4]
	   ,[Email5]
	   ,[Email6]
	   ,[Selector]
	   ,[Matching Flag]
	   ,[G20 Sel/Cat Flag]
	   ,[Weekly Violation Selector]
	   ,[Validation Status New]
	   ,[RunningTotal]
	   ,[UPC]
	   ,a.Flag_Bundle
	   ,a.[Minimum Violation Date]
	   ,a.[Minimum Listing Date]
	   ,a.[Most Recent Listing Date]
	   ,a.[Date Requested]
	   ,a.[New SKU Flag]
	   ,a.[Top_Reseller_Flag]
	   ,a.[Latest Courtesy Alert Date]
	   ,a.[Product Category Latest Courtesy Alert Date]
	   ,a.Login_Type_ID
	   ,a.[Strikethrough Flag]
	   ,a.Violation_Type
	FROM #output a
	LEFT JOIN #Product_Category b ON a.[Product Subcategory] = b.Product_Subcategory
	UNION ALL
	SELECT
		Country	
	   ,[Validation Status]
	   ,[Validation Status Weekly]	
	   ,[Fiscal Week Number]
	   ,[Week]
	   ,[Date]
	   ,b.Product_Category as [Product Category]
	   ,[Product Subcategory]	
	   ,[Product Subcategory Enforcement]
	   ,[Fact ID]
	   ,[SKU]
	   ,[ASIN]
	   ,[Product_Description]
	   ,[Account]	
	   ,[Seller Name]	
	   ,[Storefront Name(s)]
	   ,[Location ID]	
	   ,CASE WHEN [Location ID] = '99999999' THEN 'Qualified' ELSE [Seller Status] END [Seller Status]
	   ,[Termination Date]
	   ,[Seller Penalty Type]
	   ,[Reporting Group]
	   ,[Market]
	   ,[Log-in Type]
	   ,[Price Location]
	   ,[MAP]
	   ,[Advertised Price]
	   ,[Eligible IR]
	   ,[Lowest Possible Price]
	   ,[Validation_Status_Raw]
	   ,[Letter Type]
	   ,[MAP Status Detail]
	   ,[Letter Delivered Date]
	   ,[Notification Generation Date]
	   ,[Buffer Period Start]
	   ,[Buffer Period End]
	   ,[Product Suspension Start]
	   ,[Product Suspension End]
	   ,[Penalty Period Start]
	   ,[Penalty Period End]
	   ,[Screenshot_URL]
	   ,[DGF Penalty]
	   ,[Notes]
	   ,[Tier_Pass_Through]
	   ,[Category Threshold Highlight]
	   ,[Category Threshold Alert]
       ,[HP_Rep1]
       ,[HP_Rep2]
       ,[HP_Rep3]
       ,[HP_Rep4]
       ,[HP_Rep5]
       ,[HP_Rep6]
	   ,[Email1]
	   ,[Email2]
	   ,[Email3]
	   ,[Email4]
	   ,[Email5]
	   ,[Email6]
	   ,[Selector]
	   ,[Matching Flag]
	   ,[G20 Sel/Cat Flag]
	   ,[Weekly Violation Selector]
	   ,[Validation Status New]
	   ,[RunningTotal]
	   ,[UPC]
	   ,a.Flag_Bundle
	   ,a.[Minimum Violation Date]
	   ,a.[Minimum Listing Date]
	   ,a.[Most Recent Listing Date]
	   ,a.[Date Requested]
	   ,a.[New SKU FLag]
	   ,a.[Top_Reseller_Flag]
	   ,a.[Latest Courtesy Alert Date]
	   ,a.[Product Category Latest Courtesy Alert Date]
	   ,a.Login_Type_ID
	   ,a.[Strikethrough Flag]
	   ,a.Violation_Type
	FROM #ca_output a
	LEFT JOIN #Product_Category b ON a.[Product Subcategory] = b.Product_Subcategory
) a
GROUP BY Country	
	,[Validation Status]
	,[Validation Status Weekly]	
	,a.[Fiscal Week Number]
	,a.[Week]
	,a.[Date]
	,[Product Category]
	,[Product Subcategory]	
	,CASE WHEN [Product Category] = 'Large Format' THEN [Product Category]
	      WHEN [Product Category] IN ('PS','Print') THEN [Product Subcategory]
	      WHEN [Product Category] LIKE '%Supplies' THEN 'Ink & Toner' END
	,[Fact ID]
	,a.[SKU]
	,[ASIN]
	,[Product_Description]
	,CASE WHEN Country = 'US' AND a.[Location ID] = '10267108' THEN 'Office Products Center Inc' ELSE a.[Account] END
	,[Seller Name]	
	,[Storefront Name(s)]
	,a.[Location ID]	
	,[Seller Status]
	,[Termination Date]
	,[Seller Penalty Type]
	,[Reporting Group]
	,[Market]
	,[Log-in Type]
	,[Price Location]
	,[MAP]
	,[Advertised Price]
	,[Eligible IR]
	,[Lowest Possible Price]
	,[Validation_Status_Raw]
	,[Letter Type]
	,[MAP Status Detail]
	,[Letter Delivered Date]
	,[Notification Generation Date]
	,[Buffer Period Start]
	,[Buffer Period End]
	,[Product Suspension Start]
	,[Product Suspension End]
	,[Penalty Period Start]
	,[Penalty Period End]
	,[Screenshot_URL]
	,[DGF Penalty]
	,a.[Notes]
	,Tier_Pass_Through
	,[Category Threshold Highlight]
	,[Category Threshold Alert]
	,[HP_Rep1]
	,[HP_Rep2]
	,[HP_Rep3]
	,[HP_Rep4]
	,[HP_Rep5]
	,[HP_Rep6]
	,[Email1]
	,[Email2]
	,[Email3]
	,[Email4]
	,[Email5]
	,[Email6]
	,[Selector]
	,[Matching Flag]
	,[G20 Sel/Cat Flag]
	,[Weekly Violation Selector]
	,[Validation Status New]
	,RunningTotal
	,ISNULL(a.Flag_Bundle,0)
	,[Minimum Violation Date]
	,[Minimum Listing Date]
	,[Most Recent Listing Date]
	,[New SKU Flag]
	,[Top_Reseller_Flag]
	,Login_Type_ID
	,[Strikethrough Flag]
	,a.Violation_Type

DROP TABLE IF EXISTS #seller_rank
SELECT DISTINCT Country
       ,[Week]
	   ,[Product Subcategory Enforcement]
	   ,Account
	   ,[Location ID]
	   ,[Top_Reseller_Flag]
	   ,MAX(RunningTotal) MAX_Running_Total
       ,DENSE_RANK () OVER (PARTITION BY [WEEK], [Product Subcategory Enforcement] ORDER BY [Top_Reseller_Flag] DESC, MAX(RunningTotal) DESC, Account) [Weekly_Seller_Rank]
INTO #seller_rank
FROM #final_prep
GROUP BY Country
       ,[Week]
	   ,[Product Subcategory Enforcement]
	   ,Account
	   ,[Location ID]
	   ,[Top_Reseller_Flag]


-- FINAL OUTPUT AND EXPORT
DECLARE @ExportStartDate date = CASE
									WHEN @P_Export_Start_Date IS NOT NULL THEN @P_Export_Start_Date
									WHEN @P_Generate_Full_Refresh = 1 THEN '2015-09-01' -- (SELECT d.Week_Begin_Date_Alt FROM _final.Dim_Date d WITH (NOLOCK) WHERE d.Full_Date = DATETRUNC(MONTH,DATEADD(MONTH,-12,GETDATE())))
									ELSE (SELECT d.Week_Begin_Date_Alt FROM _final.Dim_Date d WITH (NOLOCK) WHERE d.Full_Date = DATETRUNC(WEEK,DATEADD(WEEK,-2,GETDATE())))
								END

/*
DECLARE @Batch_Size INT = 10000;
DECLARE @Rows_Affected INT = 1;

WHILE @Rows_Affected > 0
BEGIN
    DELETE TOP (@Batch_Size) a
    FROM _old.Violations_L12M a
    WHERE [Date] >= @ExportStartDate;

    SET @Rows_Affected = @@ROWCOUNT;
    
    WAITFOR DELAY '00:00:01';
END
*/

DELETE a
FROM _old.Violations_L12M a
WHERE [Date] >= @ExportStartDate

INSERT INTO _old.Violations_L12M
           ([Country]
           ,[Validation Status]
           ,[Validation Status Weekly]
           ,[Fiscal Week Number]
           ,[Week]
           ,[Date]
           ,[Product Category]
           ,[Product Subcategory]
           ,[Product Subcategory Enforcement]
           ,[Fact ID]
           ,[SKU]
           ,[ASIN]
           ,[Product_Description]
           ,[Account]
           ,[Seller Name]
           ,[Storefront Name(s)]
           ,[Location ID]
           ,[Seller Status]
           ,[Termination Date]
           ,[Seller Penalty Type]
           ,[Reporting Group]
           ,[Market]
           ,[Log-in Type]
           ,[Price Location]
           ,[MAP]
           ,[Advertised Price]
           ,[Eligible IR]
           ,[Lowest Possible Price]
           ,[Validation_Status_Raw]
           ,[Letter Type]
           ,[MAP Status Detail]
           ,[Letter Delivered Date]
           ,[Notification Generation Date]
           ,[Buffer Period Start]
           ,[Buffer Period End]
           ,[Product Suspension Start]
           ,[Product Suspension End]
           ,[Penalty Period Start]
           ,[Penalty Period End]
           ,[Screenshot_URL]
           ,[DGF Penalty]
           ,[Notes]
           ,[Tier_Pass_Through]
           ,[Category Threshold Highlight]
           ,[Category Threshold Alert]
           ,[HP_Rep1]
           ,[HP_Rep2]
           ,[HP_Rep3]
           ,[HP_Rep4]
           ,[HP_Rep5]
           ,[HP_Rep6]
           ,[Email1]
           ,[Email2]
           ,[Email3]
           ,[Email4]
           ,[Email5]
           ,[Email6]
           ,[Selector]
           ,[Matching Flag]
           ,[G20 Sel/Cat Flag]
           ,[Weekly Violation Selector]
           ,[Validation Status New]
           ,[RunningTotal]
           ,[UPC]
           ,[Bundle Flag]
           ,[Minimum Violation Date]
           ,[Minimum Listing Date]
           ,[Most Recent Listing Date]
           ,[Date Requested]
           ,[New SKU Flag]
           ,[Top_Reseller_Flag]
           ,[Latest Courtesy Alert Date]
		   ,[Product Category Latest Courtesy Alert Date]
           ,[Login_Type_ID]
           ,[Strikethrough Flag]
           ,[Weekly_Seller_Rank]
           ,[Price Increase SKU Flag]
           ,[Content Provider]
		   ,Partner_ID
		   ,[Violation Type])

SELECT DISTINCT
	 a.[Country]
    ,a.[Validation Status]
    ,a.[Validation Status Weekly]
    ,a.[Fiscal Week Number]
    ,a.[Week]
    ,a.[Date]
    ,a.[Product Category]
    ,a.[Product Subcategory]
    ,a.[Product Subcategory Enforcement]
    ,a.[Fact ID]
    ,a.[SKU]
    ,a.[ASIN]
    ,a.[Product_Description]
    ,a.[Account]
    ,a.[Seller Name]
    ,a.[Storefront Name(s)]
    ,a.[Location ID]
    ,a.[Seller Status]
    ,a.[Termination Date]
    ,a.[Seller Penalty Type]
    ,a.[Reporting Group]
    ,a.[Market]
    ,a.[Log-in Type]
    ,a.[Price Location]
    ,a.[MAP]
    ,a.[Advertised Price]
    ,a.[Eligible IR]
    ,a.[Lowest Possible Price]
    ,a.[Validation_Status_Raw]
    ,a.[Letter Type]
    ,a.[MAP Status Detail]
    ,a.[Letter Delivered Date]
    ,a.[Notification Generation Date]
    ,a.[Buffer Period Start]
    ,a.[Buffer Period End]
    ,a.[Product Suspension Start]
    ,a.[Product Suspension End]
    ,a.[Penalty Period Start]
    ,a.[Penalty Period End]
    ,a.[Screenshot_URL]
    ,a.[DGF Penalty]
    ,a.[Notes]
    ,a.[Tier_Pass_Through]
    ,a.[Category Threshold Highlight]
    ,a.[Category Threshold Alert]
    ,a.[HP_Rep1]
    ,a.[HP_Rep2]
    ,a.[HP_Rep3]
    ,a.[HP_Rep4]
    ,a.[HP_Rep5]
    ,a.[HP_Rep6]
    ,a.[Email1]
    ,a.[Email2]
    ,a.[Email3]
    ,a.[Email4]
    ,a.[Email5]
    ,a.[Email6]
    ,a.[Selector]
    ,a.[Matching Flag]
    ,a.[G20 Sel/Cat Flag]
    ,a.[Weekly Violation Selector]
    ,a.[Validation Status New]
    ,a.[RunningTotal]
    ,a.[UPC]
    ,a.[Bundle Flag]
    ,a.[Minimum Violation Date]
    ,a.[Minimum Listing Date]
    ,a.[Most Recent Listing Date]
    ,a.[Date Requested]
    ,a.[New SKU Flag]
    ,a.[Top_Reseller_Flag]
    ,a.[Latest Courtesy Alert Date]
	,a.[Product Category Latest Courtesy Alert Date]
    ,a.[Login_Type_ID]
    ,a.[Strikethrough Flag]
    ,b.[Weekly_Seller_Rank]
	,CASE
		WHEN a.[Bundle Flag] = 0 THEN
			CASE
				WHEN gps.SKU IS NOT NULL THEN 1
				ELSE 0
			END
		WHEN a.[Bundle Flag] = 1 THEN
			CASE
				WHEN gps_bundles.SKU IS NOT NULL THEN 1
				ELSE 0
			END
	 END [Price Increase SKU Flag]
	,con.Content_Source [Content Provider]
	,N_Partners.Id AS Partner_ID
	,ISNULL(a.Violation_Type, 'N/A') AS [Violation Type]
FROM #final_prep a
LEFT JOIN #seller_rank b ON a.Country = b.Country 
                            AND a.[Week] = b.[Week] 
                            AND a.[Product Subcategory Enforcement] = b.[Product Subcategory Enforcement] 
							AND a.[Location ID] = b.[Location ID]
LEFT JOIN #Grace_Period gps ON a.Country = gps.Country AND a.SKU = gps.SKU AND a.[Date] BETWEEN gps.Valid_From AND gps.Valid_To
LEFT JOIN #Grace_Period gps_bundles ON a.Country = gps_bundles.Country AND a.SKU LIKE '%' + gps_bundles.SKU + '%' AND a.[Date] BETWEEN gps_bundles.Valid_From AND gps_bundles.Valid_To
LEFT JOIN #Content con ON a.Country = con.Country AND a.[Location ID] = con.HPI_Location_ID
LEFT JOIN HP_QPP_Prod.dbo.N_Partners ON a.[Location ID] = N_Partners.LocationId
WHERE a.[Date] >= @ExportStartDate


IF dbo.CanSendDbMail() = 1
BEGIN
	EXEC msdb.dbo.sp_send_dbmail
			@profile_name = 'QDN Support',
			@recipients = 'pbelezhkov@dsmengines.com',
			@body = 'The _old.Violations_L12M table has been refreshed.',
			@subject = 'The Violations L12M export has been generated',
			@body_format = 'HTML';
END
END
GO

