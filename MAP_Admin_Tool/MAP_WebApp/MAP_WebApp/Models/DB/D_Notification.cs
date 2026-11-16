using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace MAP_WebApp.Models.DB
{
    public class D_Notification
    {
        public int Id { get; set; }
		//public int Notification_ID { get; set; }
		//public string Location_id { get; set; }
		//public string Seller_Name { get; set; }
		//public string Seller_DBA { get; set; }
		//public string Product_Type { get; set; }
		public int? Penalty_id { get; set; }
		//public string Penalty_Impact { get; set; }
		public string Notes { get; set; }
		//public int Policy_id { get; set; }
		//public int SellerSubType_id { get; set; }
		//public int PenaltyType_id { get; set; }
		public int? ApprovalStatus_id { get; set; }
		public int? Contacts_id { get; set; }
		//public string PartnerFirstStatusPrint { get; set; }
		//public string PartnerFirstStatusSupplies { get; set; }
		//public string PartnerFirstStatusHighest { get; set; }
		public DateTime? PreviousDeliveryDate { get; set; }
		//public string PreviousStrike { get; set; }
		public DateTime? PenaltyPeriodStart { get; set; }
		public DateTime? PenaltyPeriodEnd { get; set; }
		public DateTime? SuspensionStart { get; set; }
		public DateTime? SuspensionEnd { get; set; }
		//public decimal? AnnualSalesOutNDP { get; set; }
		//public decimal? ProductSuspensionImpact { get; set; }
		public int VisibleForHP { get; set; }
		//public string SellerPenaltyType { get; set; }
		public string C_User_ID { get; set; }
		public DateTime? C_DateTime { get; set; }
		public int ThresholdValue { get; set; }
		public bool Changed { get; set; }
		public decimal? SuppliesAlternativePercent { get; set; }
	}
}
