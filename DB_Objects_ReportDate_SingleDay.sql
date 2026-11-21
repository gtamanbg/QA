USE [HPI_MAPQC_WebTool]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- ==========================================================================================
-- Report Date single day - 11/16/26
-- The "Report Date" filter on the landing page of MAP Admin Tool now works with one day only.
-- Before: the functions below returned the notifications generated from the selected date
--         until the Saturday of the same week.
-- Now:    they return only the notifications generated on the selected date.
-- In every function the same 2 lines are changed. The old lines are commented out and the
-- new lines are placed right under them. Nothing else in the functions is changed.
-- ==========================================================================================

ALTER FUNCTION [dbo].[fn_GetNotificationList](
	@inUser_id			nvarchar(32),
	@inFromDate			datetime,
	@inPolicy			nvarchar(4000),
	@inSellerType		nvarchar(4000),
	@inSellerSubType	nvarchar(4000),
	@inPenaltyType		nvarchar(4000),
	@inSellerName		nvarchar(4000),
	@inHPApprovalStatus	nvarchar(4000),
	@inProductType		nvarchar(4000),
	@inCountry_id		int
)
RETURNS @Result TABLE(
	Id nvarchar(32) NULL,
	Policy					nvarchar(50) NULL,
	Location_id				nvarchar(20) NULL,
	Seller_Name				nvarchar(300) NULL,
	Seller_DBA				nvarchar(100) NULL,
	Product_Type			nvarchar(50) NULL,
	Penalty					nvarchar(50) NULL,
	Penalty_Impact			decimal(38,20) NULL,
	ApprovalStatus_id		int,
	Notes					nvarchar(500) NULL,
	SellerType				nvarchar(50),
	PenaltyType				nvarchar(50),
	ChangeInfo				nvarchar(MAX),
	ApprovalStatusForOrder	int,
	SellerType_id			int,
	MPASeller				nvarchar(50),
	MarketplaceViolations	nvarchar(50),
	NotificationType		int,
	Penalty_Id				int,
	Qualification_Status	nvarchar(50),
	FinStatusForOrder		int
)
AS
BEGIN
	DECLARE @User_id			nvarchar(32)	= @inUser_id
	DECLARE @FromDate			datetime		= @inFromDate
	-- Report Date single day - 11/16/26: @ToDate is the day after the selected date (before: the Saturday of the selected week)
	--DECLARE @ToDate				datetime		= DATEADD(wk, 1, DATEADD(DAY, 0-DATEPART(WEEKDAY, @inFromDate), DATEDIFF(dd, 0, @inFromDate)))
	DECLARE @ToDate				datetime		= DATEADD(DAY, 1, DATEDIFF(dd, 0, @inFromDate))
	DECLARE @Policy				nvarchar(4000)	= NULLIF(@inPolicy,'')
	DECLARE @SellerType			nvarchar(4000)	= NULLIF(@inSellerType,'')
	DECLARE @PenaltyType		nvarchar(4000)	= NULLIF(@inPenaltyType,'')
	DECLARE @SellerName			nvarchar(4000)	= NULLIF(@inSellerName,'')
	DECLARE @HPApprovalStatus	nvarchar(4000)	= NULLIF(@inHPApprovalStatus,'')
	DECLARE @SellerSubType		nvarchar(4000)	= NULLIF(@inSellerSubType,'')
	DECLARE @ProductType		nvarchar(4000)	= NULLIF(@inProductType,'')
	DECLARE @Country_id			int				= @inCountry_id


	INSERT @Result(Id,Policy,Location_id,Seller_Name,Seller_DBA,Product_Type,Penalty,Penalty_Impact,
				ApprovalStatus_id,Notes,SellerType,PenaltyType,ChangeInfo,ApprovalStatusForOrder,
				SellerType_id,MPASeller,MarketplaceViolations,NotificationType,Penalty_Id,
				Qualification_Status,FinStatusForOrder)
	SELECT DISTINCT
		H.Id,
		N_Policy.Options,
		H.Location_id,
		S.Name,--H.Seller_Name,
		COALESCE(SDBA.DBA,''),--H.Seller_DBA,
		N_ProductType.Description,--H.Product_Type,
		N_Penalty.Options AS Penalty,--H.Penalty,
		--CASE WHEN H.Penalty_id in (1,15) THEN fn_GetNotificationTotal.AdjustedPenalty ELSE H.Penalty_Impact END,--H.ProductSuspensionImpact, -- Original
		CASE
			WHEN H.Penalty_id = 1 THEN fn_GetNotificationTotal.AdjustedPenalty
			WHEN H.Penalty_id = 15 THEN CASE WHEN H.SuppliesAlternativePercent IS NULL THEN fn_GetNotificationTotal.OriginalPenalty ELSE fn_GetNotificationTotal.AdjustedPenalty END
			ELSE H.Penalty_Impact
		END,--H.ProductSuspensionImpact,
		H.ApprovalStatus_id,
		H.Notes,
		N_SellerType.Options,
		N_PenaltyType.Options,
		CASE WHEN CurrUser.UserGroup_id = 4 THEN '' ELSE '<b>Notification Id:</b> ' + CAST(H.Notification_id AS nvarchar(32)) + '</br>' END + '<b>User:</b> ' + COALESCE(N_Users.FirstName + ' ' + N_Users.LastName, H.C_User_ID, 'System') + ' </br> ' + '<b>Modified date:</b> ' + dbo.fn_GetDateTimeText(H.C_DateTime),
		CASE WHEN H.ApprovalStatus_id = 2 THEN 1 ELSE H.ApprovalStatus_id END ApprovalStatusForOrder,
		N_SellerType.Id,
		CASE H.MPASeller WHEN 1 THEN 'Yes' WHEN 0 THEN 'No' ELSE '' END,
		CASE H.MarketplaceViolations WHEN 1 THEN 'Yes' WHEN 0 THEN 'No' ELSE '' END,
		CASE
			WHEN N_Penalty.id = 15 AND H.Country_Id = 2 THEN 2
			WHEN H.Penalty_id = 1 AND H.ProductCategory_id <> 3 THEN 2
			WHEN H.Penalty_id = 1 AND H.ProductCategory_id = 3 THEN 2
			ELSE 3
		END,
		H.Penalty_id,
		N_SellerQualificationStatus.[Description] AS Qualification_Status, -- HH 04/22/24
		CASE
			WHEN N_Penalty.id = 15 THEN 1 -- Financial
			WHEN N_Penalty.id = 1 THEN 2 -- DGF
			ELSE 3
		END AS FinStatusForOrder-- HH 04/22/24
	FROM D_Notification H WITH(NOLOCK)
	--INNER JOIN D_NotificationDetail D WITH(NOLOCK) ON D.Master_Id = H.Id
	LEFT JOIN N_Policy WITH(NOLOCK) ON N_Policy.Id = H.Policy_id
	LEFT JOIN N_ApprovalStatus WITH(NOLOCK) ON N_ApprovalStatus.Id = H.ApprovalStatus_id
	LEFT JOIN N_SellerSubType WITH(NOLOCK) ON N_SellerSubType.Id = H.SellerSubType_id
	LEFT JOIN N_SellerType WITH(NOLOCK) ON N_SellerType.Id = N_SellerSubType.SellerType_id
	LEFT JOIN N_PenaltyType WITH(NOLOCK) ON N_PenaltyType.Id = H.PenaltyType_id
	LEFT JOIN N_Users ON N_Users.Id = H.C_User_ID
	LEFT JOIN N_Users CurrUser ON CurrUser.Id = @User_id
	OUTER APPLY fn_GetNotificationTotal(@User_id,H.Id)
	LEFT JOIN N_Seller S WITH(NOLOCK) ON S.Id = H.Seller_id
	LEFT JOIN N_SellerDBA SDBA WITH(NOLOCK) ON SDBA.Id = H.SellerDBA_id
	LEFT JOIN N_ProductType WITH(NOLOCK) ON N_ProductType.Id = H.ProductType_id
	LEFT JOIN N_Penalty WITH(NOLOCK) ON N_Penalty.Id = H.Penalty_id
	LEFT JOIN N_SellerQualificationStatus WITH(NOLOCK) ON N_SellerQualificationStatus.Id = H.SellerQualificationStatus_id -- HH 04/22/24
	WHERE H.Country_Id = @Country_id
		  AND ((@FromDate IS NULL) OR ((@FromDate IS NOT NULL) AND (H.GenerationDate >= @FromDate)))
		  -- Report Date single day - 11/16/26: "<" instead of "<=", so only the notifications generated on the selected date are returned
		  --AND ((@ToDate IS NULL) OR ((@ToDate IS NOT NULL) AND (H.GenerationDate <= @ToDate)))
		  AND ((@ToDate IS NULL) OR ((@ToDate IS NOT NULL) AND (H.GenerationDate < @ToDate)))
		  AND ((@Policy IS NOT NULL) AND (H.Policy_id in (SELECT Value FROM fn_Split(@Policy,','))))
		  AND ((@SellerType IS NOT NULL) AND (N_SellerType.Id in (SELECT Value FROM fn_Split(@SellerType,','))))
		  AND ((@SellerSubType IS NOT NULL) AND (N_SellerSubType.Description in (SELECT Value FROM fn_Split(@SellerSubType,','))))
		  AND ((@PenaltyType IS NOT NULL) AND (H.PenaltyType_id in (SELECT Value FROM fn_Split(@PenaltyType,','))))
		  AND ((@SellerName IS NOT NULL) AND (H.Seller_id in (SELECT Value FROM fn_Split(@SellerName,','))))
		  AND ((@HPApprovalStatus IS NOT NULL) AND (H.ApprovalStatus_id in (SELECT Value FROM fn_Split(@HPApprovalStatus,','))))
		  AND ((@ProductType IS NOT NULL) AND (H.ProductType_id in (SELECT Value FROM fn_Split(@ProductType,','))))
		  AND (
				(CurrUser.UserGroup_Id = 1) OR
				(CurrUser.UserGroup_Id = 2) OR
				(CurrUser.UserGroup_Id = 3) OR
				(CurrUser.UserGroup_Id = 4 AND H.VisibleForHP = 1)
			  )

	RETURN
END
GO

ALTER FUNCTION [dbo].[fn_GetSellerList](
	@inUser_id				nvarchar(32),
	@inFromDate				datetime,
	@inPolicy				nvarchar(4000),
	@inSellerType			nvarchar(4000),
	@inSellerSubType		nvarchar(4000),
	@inPenaltyType			nvarchar(4000),
	@inSellerName			nvarchar(4000),
	@inHPApprovalStatus		nvarchar(4000),
	@inProductType			nvarchar(4000),
	@inAllSellerSelected	int,
	@inCountry_id			int
)
RETURNS @Result TABLE(
	Id			int,
	Options		nvarchar(300) NULL,
	IsSelected	int
)
AS
BEGIN
	DECLARE @User_id			nvarchar(32)	= @inUser_id
	DECLARE @FromDate			datetime		= @inFromDate
	-- Report Date single day - 11/16/26: @ToDate is the day after the selected date (before: the Saturday of the selected week)
	--DECLARE @ToDate				datetime		= DATEADD(wk, 1, DATEADD(DAY, 0-DATEPART(WEEKDAY, @inFromDate), DATEDIFF(dd, 0, @inFromDate)))
	DECLARE @ToDate				datetime		= DATEADD(DAY, 1, DATEDIFF(dd, 0, @inFromDate))
	DECLARE @Policy				nvarchar(4000)	= NULLIF(@inPolicy,'')
	DECLARE @SellerType			nvarchar(4000)	= NULLIF(@inSellerType,'')
	DECLARE @PenaltyType		nvarchar(4000)	= NULLIF(@inPenaltyType,'')
	DECLARE @SellerName			nvarchar(4000)	= NULLIF(@inSellerName,'')
	DECLARE @HPApprovalStatus	nvarchar(4000)	= NULLIF(@inHPApprovalStatus,'')
	DECLARE @SellerSubType		nvarchar(4000)	= NULLIF(@inSellerSubType,'')
	DECLARE @ProductType		nvarchar(4000)	= NULLIF(@inProductType,'')
	DECLARE @AllSellerSelected	int				= COALESCE(@inAllSellerSelected,1)
	DECLARE @Country_id			int				= @inCountry_id

	INSERT @Result(Id,Options,IsSelected)
	SELECT DISTINCT
		S.Id,
		S.Name,
		CASE
			WHEN @AllSellerSelected = 1 THEN 1
			WHEN S.id in (SELECT Value FROM fn_Split(@SellerName,',')) THEN 1
			ELSE 0
		END
	FROM D_Notification H WITH(NOLOCK)
	--INNER JOIN D_NotificationDetail D WITH(NOLOCK) ON D.Master_Id = H.Id
	LEFT JOIN N_SellerSubType WITH(NOLOCK) ON N_SellerSubType.Id = H.SellerSubType_id
	LEFT JOIN N_SellerType WITH(NOLOCK) ON N_SellerType.Id = N_SellerSubType.SellerType_id
	LEFT JOIN N_Users CurrUser ON CurrUser.Id = @User_id
	LEFT JOIN N_Seller S WITH(NOLOCK) ON S.Id = H.Seller_id
	WHERE H.Country_Id = @Country_id
		  AND H.Seller_id IS NOT NULL
		  AND ((@FromDate IS NULL) OR ((@FromDate IS NOT NULL) AND (H.GenerationDate >= @FromDate)))
		  -- Report Date single day - 11/16/26: "<" instead of "<=", so only the notifications generated on the selected date are returned
		  --AND ((@ToDate IS NULL) OR ((@ToDate IS NOT NULL) AND (H.GenerationDate <= @ToDate)))
		  AND ((@ToDate IS NULL) OR ((@ToDate IS NOT NULL) AND (H.GenerationDate < @ToDate)))
		  AND ((@Policy IS NOT NULL) AND (H.Policy_id in (SELECT Value FROM fn_Split(@Policy,','))))
		  AND ((@SellerType IS NOT NULL) AND (N_SellerType.Id in (SELECT Value FROM fn_Split(@SellerType,','))))
		  AND ((@SellerSubType IS NOT NULL) AND (N_SellerSubType.Description in (SELECT Value FROM fn_Split(@SellerSubType,','))))
		  AND ((@PenaltyType IS NOT NULL) AND (H.PenaltyType_id in (SELECT Value FROM fn_Split(@PenaltyType,','))))
		  AND ((@HPApprovalStatus IS NOT NULL) AND (H.ApprovalStatus_id in (SELECT Value FROM fn_Split(@HPApprovalStatus,','))))
		  AND ((@ProductType IS NOT NULL) AND (H.ProductType_id in (SELECT Value FROM fn_Split(@ProductType,','))))
		  AND (
				(CurrUser.UserGroup_Id = 1) OR
				(CurrUser.UserGroup_Id = 2) OR
				(CurrUser.UserGroup_Id = 3) OR
				(CurrUser.UserGroup_Id = 4 AND H.VisibleForHP = 1)
			  )

	RETURN
END
GO

ALTER FUNCTION [dbo].[fn_GetNotificationContactList](
	@inUser_id			nvarchar(32),
	@inFromDate			datetime,
	@inPolicy			nvarchar(4000),
	@inSellerType		nvarchar(4000),
	@inSellerSubType	nvarchar(4000),
	@inPenaltyType		nvarchar(4000),
	@inSellerName		nvarchar(4000),
	@inHPApprovalStatus	nvarchar(4000),
	@inProductType		nvarchar(4000),
	@inCountry_id		int
)
RETURNS @Result TABLE(
	Id							int,
	Seller_Id					int,
	Seller_Name					nvarchar(300),
	LID							nvarchar(20),
	ProductCategory				nvarchar(100),
	IntContact1_eMail			nvarchar(100),
	IntContact2_eMail			nvarchar(100),
	IntContact3_eMail			nvarchar(100),
	IntContact4_eMail			nvarchar(100),
	IntContact5_eMail			nvarchar(100),
	IntContact6_eMail			nvarchar(100),
	Country						nvarchar(50)
)
AS
BEGIN
	DECLARE @User_id			nvarchar(32)	= @inUser_id
	DECLARE @FromDate			datetime		= @inFromDate
	-- Report Date single day - 11/16/26: @ToDate is the day after the selected date (before: the Saturday of the selected week)
	--DECLARE @ToDate				datetime		= DATEADD(wk, 1, DATEADD(DAY, 0-DATEPART(WEEKDAY, @inFromDate), DATEDIFF(dd, 0, @inFromDate)))
	DECLARE @ToDate				datetime		= DATEADD(DAY, 1, DATEDIFF(dd, 0, @inFromDate))
	DECLARE @Policy				nvarchar(4000)	= NULLIF(@inPolicy,'')
	DECLARE @SellerType			nvarchar(4000)	= NULLIF(@inSellerType,'')
	DECLARE @PenaltyType		nvarchar(4000)	= NULLIF(@inPenaltyType,'')
	DECLARE @SellerName			nvarchar(4000)	= NULLIF(@inSellerName,'')
	DECLARE @HPApprovalStatus	nvarchar(4000)	= NULLIF(@inHPApprovalStatus,'')
	DECLARE @SellerSubType		nvarchar(4000)	= NULLIF(@inSellerSubType,'')
	DECLARE @ProductType		nvarchar(4000)	= NULLIF(@inProductType,'')
	DECLARE @Country_id			int				= @inCountry_id


	INSERT @Result(Id,Seller_Id,Seller_Name,LID,ProductCategory,IntContact1_eMail,IntContact2_eMail,
		IntContact3_eMail,IntContact4_eMail,IntContact5_eMail,IntContact6_eMail,Country)
	SELECT
		DENSE_RANK() OVER(ORDER BY Id,COALESCE(CategoryEMail,'')) Ranking,
		Id,
		Seller_Name,
		Location_id,
		CategoryEMail,
		IntContact1_eMail,
		IntContact2_eMail,
		IntContact3_eMail,
		IntContact4_eMail,
		IntContact5_eMail,
		IntContact6_eMail,
		CountryName
	FROM (
		SELECT DISTINCT
			DENSE_RANK() OVER(PARTITION BY S.Id, COALESCE(C.CategoryEMail,'') ORDER BY S.Id,
			COALESCE(S.Name,''),COALESCE(H.Location_id,''),COALESCE(C.CategoryEMail,''),
			COALESCE(C.Email1,'') DESC,COALESCE(C.Email2,'') DESC,COALESCE(C.Email3,'') DESC,
			COALESCE(C.Email4,'') DESC,COALESCE(C.Email5,'') DESC,COALESCE(C.Email6,'') DESC ) AS Ranking,
			S.Id,
			COALESCE(S.Name,'') AS Seller_Name,--H.Seller_Name,
			COALESCE(H.Location_id,'') AS Location_id,
			COALESCE(C.CategoryEMail,'') AS CategoryEMail,--COALESCE(N_ProductCategory.Options,''),--H.Product_Type,
			COALESCE(C.Email1,'') AS IntContact1_eMail,
			COALESCE(C.Email2,'') AS IntContact2_eMail,
			COALESCE(C.Email3,'') AS IntContact3_eMail,
			COALESCE(C.Email4,'') AS IntContact4_eMail,
			COALESCE(C.Email5,'') AS IntContact5_eMail,
			COALESCE(C.Email6,'') AS IntContact6_eMail,
			CN.Name AS CountryName
		FROM D_Notification H WITH(NOLOCK)
		INNER JOIN D_NotificationContact C WITH(NOLOCK) ON C.Id = H.Contacts_id
		LEFT JOIN N_SellerSubType WITH(NOLOCK) ON N_SellerSubType.Id = H.SellerSubType_id
		LEFT JOIN N_SellerType WITH(NOLOCK) ON N_SellerType.Id = N_SellerSubType.SellerType_id
		LEFT JOIN N_Users CurrUser ON CurrUser.Id = @User_id
		LEFT JOIN N_Seller S WITH(NOLOCK) ON S.Id = H.Seller_id
		LEFT JOIN N_Country CN WITH(NOLOCK) ON CN.Id = H.Country_Id
		WHERE H.Country_Id = @Country_id
			AND ((@FromDate IS NULL) OR ((@FromDate IS NOT NULL) AND (H.GenerationDate >= @FromDate)))
			-- Report Date single day - 11/16/26: "<" instead of "<=", so only the notifications generated on the selected date are returned
			--AND ((@ToDate IS NULL) OR ((@ToDate IS NOT NULL) AND (H.GenerationDate <= @ToDate)))
			AND ((@ToDate IS NULL) OR ((@ToDate IS NOT NULL) AND (H.GenerationDate < @ToDate)))
			AND ((@Policy IS NOT NULL) AND (H.Policy_id in (SELECT Value FROM fn_Split(@Policy,','))))
			AND ((@SellerType IS NOT NULL) AND (N_SellerType.Id in (SELECT Value FROM fn_Split(@SellerType,','))))
			AND ((@SellerSubType IS NOT NULL) AND (N_SellerSubType.Description in (SELECT Value FROM fn_Split(@SellerSubType,','))))
			AND ((@PenaltyType IS NOT NULL) AND (H.PenaltyType_id in (SELECT Value FROM fn_Split(@PenaltyType,','))))
			AND ((@SellerName IS NOT NULL) AND (H.Seller_id in (SELECT Value FROM fn_Split(@SellerName,','))))
			AND ((@HPApprovalStatus IS NOT NULL) AND (H.ApprovalStatus_id in (SELECT Value FROM fn_Split(@HPApprovalStatus,','))))
			AND ((@ProductType IS NOT NULL) AND (H.ApprovalStatus_id in (SELECT Value FROM fn_Split(@ProductType,','))))
			AND (
				(CurrUser.UserGroup_Id = 1) OR
				(CurrUser.UserGroup_Id = 2) OR
				(CurrUser.UserGroup_Id = 3) OR
				(CurrUser.UserGroup_Id = 4 AND H.VisibleForHP = 1)
				)
			AND H.ApprovalStatus_id < 4
	)T
	WHERE Ranking = 1
	ORDER BY Id,CategoryEMail

	RETURN
END
GO

ALTER FUNCTION [dbo].[fn_GetNotificationForExport](
	@inUser_id			nvarchar(32),
	@inFromDate			datetime,
	@inPolicy			nvarchar(4000),
	@inSellerType		nvarchar(4000),
	@inSellerSubType	nvarchar(4000),
	@inPenaltyType		nvarchar(4000),
	@inSellerName		nvarchar(4000),
	@inHPApprovalStatus	nvarchar(4000),
	@inProductType		nvarchar(4000),
	@inCountry_id		int
)
RETURNS @Result TABLE(
	Country nvarchar(50),
	Policy nvarchar(50),
	Location_id nvarchar(20),
	Seller_Name nvarchar(300),
	Seller_DBA nvarchar(100),
	Product_Type nvarchar(20),
	Penalty nvarchar(50) NULL,
	Penalty_Impact nvarchar(50)
)
AS
BEGIN
	DECLARE @User_id			nvarchar(32)	= @inUser_id
	DECLARE @FromDate			datetime		= @inFromDate
	-- Report Date single day - 11/16/26: @ToDate is the day after the selected date (before: the Saturday of the selected week)
	--DECLARE @ToDate				datetime		= DATEADD(wk, 1, DATEADD(DAY, 0-DATEPART(WEEKDAY, @inFromDate), DATEDIFF(dd, 0, @inFromDate)))
	DECLARE @ToDate				datetime		= DATEADD(DAY, 1, DATEDIFF(dd, 0, @inFromDate))
	DECLARE @Policy				nvarchar(4000)	= NULLIF(@inPolicy,'')
	DECLARE @SellerType			nvarchar(4000)	= NULLIF(@inSellerType,'')
	DECLARE @PenaltyType		nvarchar(4000)	= NULLIF(@inPenaltyType,'')
	DECLARE @SellerName			nvarchar(4000)	= NULLIF(@inSellerName,'')
	DECLARE @HPApprovalStatus	nvarchar(4000)	= NULLIF(@inHPApprovalStatus,'')
	DECLARE @SellerSubType		nvarchar(4000)	= NULLIF(@inSellerSubType,'')
	DECLARE @ProductType		nvarchar(4000)	= NULLIF(@inProductType,'')
	DECLARE @Country_id			int				= @inCountry_id

	INSERT @Result(Country,Policy,Location_id,Seller_Name,Seller_DBA,Product_Type,Penalty,Penalty_Impact)
	SELECT DISTINCT
		C.Name,
		N_Policy.Options,
		H.Location_id,
		S.Name,--H.Seller_Name,
		COALESCE(SDBA.DBA,''),--H.Seller_DBA,
		N_ProductType.Description,--H.Product_Type,
		N_Penalty.Options AS Penalty,--H.Penalty,
		COALESCE(CASE
			WHEN H.Penalty_id in (1,15) THEN CAST(CAST(COALESCE(fn_GetNotificationTotal.AdjustedPenalty,0) AS Decimal(28,10)) AS nvarchar(50))
			ELSE H.Penalty_Impact
		END,'na')
	FROM D_Notification H WITH(NOLOCK)
	INNER JOIN D_NotificationDetail D WITH(NOLOCK) ON D.Master_Id = H.Id
	LEFT JOIN N_Policy WITH(NOLOCK) ON N_Policy.Id = H.Policy_id
	LEFT JOIN N_ApprovalStatus WITH(NOLOCK) ON N_ApprovalStatus.Id = H.ApprovalStatus_id
	LEFT JOIN N_SellerSubType WITH(NOLOCK) ON N_SellerSubType.Id = H.SellerSubType_id
	LEFT JOIN N_SellerType WITH(NOLOCK) ON N_SellerType.Id = N_SellerSubType.SellerType_id
	--LEFT JOIN N_PenaltyType WITH(NOLOCK) ON N_PenaltyType.Id = H.PenaltyType_id
	LEFT JOIN N_Users ON N_Users.Id = H.C_User_ID
	OUTER APPLY fn_GetNotificationTotal(@User_id,H.Id)
	LEFT JOIN N_Users CurrUser ON CurrUser.Id = @User_id
	LEFT JOIN N_Seller S WITH(NOLOCK) ON S.Id = H.Seller_id
	LEFT JOIN N_SellerDBA SDBA WITH(NOLOCK) ON SDBA.Id = H.SellerDBA_id
	LEFT JOIN N_ProductType WITH(NOLOCK) ON N_ProductType.Id = H.ProductType_id
	LEFT JOIN N_Penalty WITH(NOLOCK) ON N_Penalty.Id = H.Penalty_id
	LEFT JOIN N_Country C WITH(NOLOCK) ON C.Id = H.Country_Id
	WHERE H.Country_Id = @Country_id
		  AND ((@FromDate IS NULL) OR ((@FromDate IS NOT NULL) AND (H.GenerationDate >= @FromDate)))
		  -- Report Date single day - 11/16/26: "<" instead of "<=", so only the notifications generated on the selected date are returned
		  --AND ((@ToDate IS NULL) OR ((@ToDate IS NOT NULL) AND (H.GenerationDate <= @ToDate)))
		  AND ((@ToDate IS NULL) OR ((@ToDate IS NOT NULL) AND (H.GenerationDate < @ToDate)))
		  AND ((@Policy IS NOT NULL) AND (H.Policy_id in (SELECT Value FROM fn_Split(@Policy,','))))
		  AND ((@SellerType IS NOT NULL) AND (N_SellerType.Id in (SELECT Value FROM fn_Split(@SellerType,','))))
		  AND ((@SellerSubType IS NOT NULL) AND (N_SellerSubType.Description in (SELECT Value FROM fn_Split(@SellerSubType,','))))
		  AND ((@PenaltyType IS NOT NULL) AND (H.PenaltyType_id in (SELECT Value FROM fn_Split(@PenaltyType,','))))
		  AND ((@SellerName IS NOT NULL) AND (H.Seller_id in (SELECT Value FROM fn_Split(@SellerName,','))))
		  AND ((@HPApprovalStatus IS NOT NULL) AND (H.ApprovalStatus_id in (SELECT Value FROM fn_Split(@HPApprovalStatus,','))))
		  AND ((@ProductType IS NOT NULL) AND (H.ProductType_id in (SELECT Value FROM fn_Split(@ProductType,','))))
		  AND (
				(CurrUser.UserGroup_Id = 1) OR
				(CurrUser.UserGroup_Id = 2) OR
				(CurrUser.UserGroup_Id = 3) OR
				(CurrUser.UserGroup_Id = 4 AND H.VisibleForHP = 1)
			  )

	RETURN
END
GO

ALTER FUNCTION [dbo].[fn_GetNotificationDetailsForExport](
	@inUser_id			nvarchar(32),
	@inFromDate			datetime,
	@inPolicy			nvarchar(4000),
	@inSellerType		nvarchar(4000),
	@inSellerSubType	nvarchar(4000),
	@inPenaltyType		nvarchar(4000),
	@inSellerName		nvarchar(4000),
	@inHPApprovalStatus nvarchar(4000),
	@inProductType		nvarchar(4000),
	@inCountry_id		int
)
RETURNS @Result TABLE(
	Country nvarchar(50),
	Policy nvarchar(50) NULL,
	Location_id nvarchar(20) NULL,
	Seller_Name nvarchar(300) NULL,
	Seller_DBA nvarchar(100) NULL,
	Penalty nvarchar(50) NULL,
	Penalty_Impact nvarchar(50),
	Product_Type nvarchar(20) NULL,
	Product_Line nvarchar(5) NULL,
	SKU nvarchar(255),
	ProductDescription nvarchar(300),
	Collected_Date nvarchar(50),
	Screenshot_URL nvarchar(500),
	Seller_Advertised_Price decimal(28,10),
	Lowest_Possible_Price decimal(28,10),
	MAP decimal(38,20),
	MAPAdvertisedPriceDiff decimal(38, 20),
	Eligible_IR_Amount decimal(28,10)
)
AS
BEGIN
	DECLARE @User_id			nvarchar(32)	= @inUser_id
	DECLARE @FromDate			datetime		= @inFromDate
	-- Report Date single day - 11/16/26: @ToDate is the day after the selected date (before: the Saturday of the selected week)
	--DECLARE @ToDate				datetime		= DATEADD(wk, 1, DATEADD(DAY, 0-DATEPART(WEEKDAY, @inFromDate), DATEDIFF(dd, 0, @inFromDate)))
	DECLARE @ToDate				datetime		= DATEADD(DAY, 1, DATEDIFF(dd, 0, @inFromDate))
	DECLARE @Policy				nvarchar(4000)	= NULLIF(@inPolicy,'')
	DECLARE @SellerType			nvarchar(4000)	= NULLIF(@inSellerType,'')
	DECLARE @PenaltyType		nvarchar(4000)	= NULLIF(@inPenaltyType,'')
	DECLARE @SellerName			nvarchar(4000)	= NULLIF(@inSellerName,'')
	DECLARE @HPApprovalStatus	nvarchar(4000)	= NULLIF(@inHPApprovalStatus,'')
	DECLARE @SellerSubType		nvarchar(4000)	= NULLIF(@inSellerSubType,'')
	DECLARE @ProductType		nvarchar(4000)	= NULLIF(@inProductType,'')
	DECLARE @Country_id			int				= @inCountry_id

	INSERT @Result(Country,Policy,Location_id,Seller_Name,Seller_DBA,Penalty,Penalty_Impact,Product_Type,Product_Line,SKU,
			ProductDescription,Collected_Date,Screenshot_URL,Seller_Advertised_Price,Lowest_Possible_Price,MAP,
			MAPAdvertisedPriceDiff,Eligible_IR_Amount)
	SELECT
		C.Name,
		N_Policy.Options,
		H.Location_id,
		S.Name,--H.Seller_Name,
		SDBA.DBA,--H.Seller_DBA,
		N_Penalty.Options AS Penalty,--H.Penalty,
		COALESCE(CASE
			WHEN H.Penalty_id = 1 AND H.ProductCategory_id in (1,2,5) THEN CAST(CAST(COALESCE(Alternative_Penalty,Three_Percent_of_Total,0) AS Decimal(28,10)) AS nvarchar(50))
			WHEN (H.Penalty_id = 1 AND H.ProductCategory_id = 3) OR (N_Penalty.id = 15 AND H.Country_Id = 2) THEN CAST(CASE WHEN H.Penalty_Impact IS NOT NULL THEN CAST(COALESCE(H.Penalty_Impact,'0.00') AS Decimal(28,10)) ELSE H.Penalty_Impact END AS nvarchar(50))
			ELSE COALESCE(CAST(CAST(H.Penalty_Impact AS Decimal(28,10)) AS nvarchar(50)),N_Penalty.Options)
		END,'n/a'),
		N_ProductType.Description,--H.Product_Type,
		D.Product_Line,
		D.SKU,
		D.Product_description,
		CONVERT(nvarchar(10),D.Collected_Date,101),
		D.Screenshot_URL,
		D.Seller_Advertised_Price,
		D.Lowest_Possible_Price,
		D.MAP,
		COALESCE(D.MAP,0) - COALESCE(D.Seller_Advertised_Price,0) MAPAdvertisedPriceDiff,
		D.Eligible_IR_Amount
	FROM D_Notification H WITH(NOLOCK)
	INNER JOIN D_NotificationDetail D WITH(NOLOCK) ON D.Master_Id = H.Id
	LEFT JOIN N_Policy WITH(NOLOCK) ON N_Policy.Id = H.Policy_id
	LEFT JOIN N_ApprovalStatus WITH(NOLOCK) ON N_ApprovalStatus.Id = H.ApprovalStatus_id
	LEFT JOIN N_SellerSubType WITH(NOLOCK) ON N_SellerSubType.Id = H.SellerSubType_id
	LEFT JOIN N_SellerType WITH(NOLOCK) ON N_SellerType.Id = N_SellerSubType.SellerType_id
	LEFT JOIN N_Users ON N_Users.Id = H.C_User_ID
	LEFT JOIN N_Seller S WITH(NOLOCK) ON S.Id = H.Seller_id
	LEFT JOIN N_SellerDBA SDBA WITH(NOLOCK) ON SDBA.Id = H.SellerDBA_id
	LEFT JOIN N_ProductType WITH(NOLOCK) ON N_ProductType.Id = H.ProductType_id
	LEFT JOIN N_SellerPenaltyType WITH(NOLOCK) ON N_SellerPenaltyType.Id = H.SellerPenaltyType_id
	LEFT JOIN N_PartnerStatus PFSS WITH(NOLOCK) ON PFSS.Id = H.PartnerFirstStatusSupplies_id
	LEFT JOIN N_PartnerStatus PFSP WITH(NOLOCK) ON PFSP.Id = H.PartnerFirstStatusPrint_id
	LEFT JOIN N_Penalty  WITH(NOLOCK) ON N_Penalty.Id = H.Penalty_id
	OUTER APPLY fn_GetNotificationTotal(@User_id,H.Id)
	LEFT JOIN N_Users CurrUser ON CurrUser.Id = @User_id
	LEFT JOIN N_Country C WITH(NOLOCK) ON C.Id = H.Country_Id
	WHERE H.Country_Id = @Country_id
		  AND ((@FromDate IS NULL) OR ((@FromDate IS NOT NULL) AND (H.GenerationDate >= @FromDate)))
		  -- Report Date single day - 11/16/26: "<" instead of "<=", so only the notifications generated on the selected date are returned
		  --AND ((@ToDate IS NULL) OR ((@ToDate IS NOT NULL) AND (H.GenerationDate <= @ToDate)))
		  AND ((@ToDate IS NULL) OR ((@ToDate IS NOT NULL) AND (H.GenerationDate < @ToDate)))
		  AND ((@Policy IS NOT NULL) AND (H.Policy_id in (SELECT Value FROM fn_Split(@Policy,','))))
		  AND ((@SellerType IS NOT NULL) AND (N_SellerType.Id in (SELECT Value FROM fn_Split(@SellerType,','))))
		  AND ((@SellerSubType IS NOT NULL) AND (N_SellerSubType.Description in (SELECT Value FROM fn_Split(@SellerSubType,','))))
		  AND ((@PenaltyType IS NOT NULL) AND (H.PenaltyType_id in (SELECT Value FROM fn_Split(@PenaltyType,','))))
		  AND ((@SellerName IS NOT NULL) AND (H.Seller_id in (SELECT Value FROM fn_Split(@SellerName,','))))
		  AND ((@HPApprovalStatus IS NOT NULL) AND (H.ApprovalStatus_id in (SELECT Value FROM fn_Split(@HPApprovalStatus,','))))
		  AND ((@ProductType IS NOT NULL) AND (H.ApprovalStatus_id in (SELECT Value FROM fn_Split(@ProductType,','))))
		  AND (
				(CurrUser.UserGroup_Id = 1) OR
				(CurrUser.UserGroup_Id = 2) OR
				(CurrUser.UserGroup_Id = 3) OR
				(CurrUser.UserGroup_Id = 4 AND H.VisibleForHP = 1)
			  )
		  AND D.ApprovalStatus_id = 2

	RETURN
END
GO
