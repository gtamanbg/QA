namespace MAP_WebApp.Models.DB
{
    public class fn_GetNotificationList
    {
        public string Id { get; set; }
        public string Policy { get; set; }
        public string Location_id { get; set; }
        public string Seller_Name { get; set; }
        public string Seller_DBA { get; set; }
        public string Product_Type{ get; set; }
        public string Penalty { get; set; }
        public decimal? Penalty_Impact { get; set; }
        public int ApprovalStatus_id { get; set; }
        public string Notes { get; set; }
        public string SellerType { get; set; }
        public string PenaltyType { get; set; }
        public string ChangeInfo { get; set; }
        public int ApprovalStatusForOrder { get; set; }
        public int SellerType_id { get; set; }
        public string MPASeller { get; set; }
        public string MarketplaceViolations { get; set; }
        public int NotificationType { get; set; }
        public int? Penalty_Id { get; set; }
        public string Qualification_Status { get; set; }
        public int FinStatusForOrder {  get; set; }  
    }
}
