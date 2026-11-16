namespace MAP_WebApp.Models.DB
{
    public class fn_GetNotificaitonInfo
    {
        public int Id { get; set; }
        public string LID { get; set; }
        public string Seller_Name { get; set; }
        public string Seller_DBA { get; set; }
        public string Product_Type { get; set; }
        public string SellerPenaltyType { get; set; }
        public string Penalty { get; set; }
        public int Contacts_id { get; set; }
        public string AccContact1_eMail { get; set; }
        public string AccContact2_eMail { get; set; }
        public string AccContact3_eMail { get; set; }
        public string AccContact4_eMail { get; set; }
        public string AccContact5_eMail { get; set; }
        public string AccContact6_eMail { get; set; }
        public string IntContact1_eMail { get; set; }
        public string IntContact2_eMail { get; set; }
        public string IntContact3_eMail { get; set; }
        public string IntContact4_eMail { get; set; }
        public string IntContact5_eMail { get; set; }
        public string IntContact6_eMail { get; set; }
        public decimal OriginalPenalty { get; set; }
        public decimal AdjustedPenalty { get; set; }
        public int Approval_Status_id { get; set; }
        public string Approval_Status { get; set; }
        public string Reviewee_Notes { get; set; }
        public string PartnerFirstStatusSupplies { get; set; }
        public string PartnerFirstStatusPrint { get; set; }
        public string AnnualSalesOutNDP { get; set; }
        public decimal? ProductSuspensionImpact { get; set; }
        public string PreviousStrike { get; set; }
        public string PreviousDeliveryDate { get; set; }
        public string PenaltyPeriodStart { get; set; }
        public string PenaltyPeriodEnd { get; set; }
        public string SuspensionStart { get; set; }
        public string SuspensionEnd { get; set; }
        public string Address { get; set; }
        public string City { get; set; }
        public string State { get; set; }
        public string Zip { get; set; }
        public int VisibleForHP { get; set; }
        public int ShowVisibleForHP { get; set; }
        public int ShowReplacement { get; set; }
        public string SellerSubTypeDescription { get; set; }
        public int RemoveRepButton { get; set; }
        public int HideDates { get; set; }
        public int? State_id { get; set; }
        public string ReportPeriod { get; set; }
        public string StoreFrontName { get; set; }
        public int HideReason { get; set; }
        public int HideHPReason { get; set; }
        public decimal? SuppliesAlternativePercent { get; set; }
        public int Country_id { get; set; }
        public decimal? BasePenalty { get; set; }
    }
}
