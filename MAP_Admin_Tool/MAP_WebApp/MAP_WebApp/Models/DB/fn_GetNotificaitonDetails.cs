using System;

namespace MAP_WebApp.Models.DB
{
    public class fn_GetNotificaitonDetails
    {
        public string Id { get; set; }
        public int Master_Id { get; set; }
        public DateTime Collected_Date { get; set; }
        public string sCollected_Date { get; set; }
        public string Data_Source { get; set; }
        public string Product_Type { get; set; }
        public string Product_Line { get; set; }
        public string SKU { get; set; }
        public string Product_Description { get; set; }
        public string Market { get; set; }
        public string Price_Location { get; set; }
        public string Screenshot_URL { get; set; }
        public decimal? Seller_Advertised_Price { get; set; }
        public decimal? Lowest_Possible_Price { get; set; }
        public decimal? MAP { get; set; }
        public decimal? Eligible_IR_Amount { get; set; }
        public Int16 Violation_Code { get; set; }
        public decimal? Total_Penalty { get; set; }
        public decimal? Three_Percent_of_Total { get; set; }
        public decimal? Alternative_Percent_Amount { get; set; }
        public decimal? Alternative_Penalty { get; set; }
        public int ApprovalStatus_id { get; set; }
        public string Notes { get; set; }
        public bool SampleProof { get; set; }
        public int? Reason_id { get; set; }
        public string Reason_Description { get; set; }
        public int? HPReason_id { get; set; }
        public string HPReason_Description { get; set; }
        public decimal? MAPAdvertisedPriceDiff { get; set; }
        public string ChangeInfo { get; set; }
        public decimal? TierPassThrough { get; set; }
    }
}
