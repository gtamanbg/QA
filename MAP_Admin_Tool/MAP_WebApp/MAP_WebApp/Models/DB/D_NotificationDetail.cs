using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace MAP_WebApp.Models.DB
{
    public class D_NotificationDetail
    {
        public string Id { get; set; }
        public int Master_id { get; set; }
        public bool SampleProof { get; set; }
        public decimal? Alternative_Percent_Amount { get; set; }
        public decimal? Alternative_Penalty { get; set; }
        public decimal? Total_Penalty { get; set; }
        public decimal? Three_Percent_of_Total { get; set; }
        public int ApprovalStatus_id { get; set; }
        public string Notes { get; set; }
        public string C_User_ID { get; set; }
        public DateTime C_DateTime { get; set; }
        public int? Reason_id { get; set; }
        public int? HPReason_id { get; set; }
        public bool Changed { get; set; }
    }
}
