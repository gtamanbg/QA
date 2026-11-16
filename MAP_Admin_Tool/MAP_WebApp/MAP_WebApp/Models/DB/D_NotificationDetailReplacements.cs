using System;

namespace MAP_WebApp.Models.DB
{
    public class D_NotificationDetailReplacements
    {
        public string Id { get; set; }
        public int Master_id { get; set; }
        public int ReplacementApprovalStatus_Id { get; set; }
        public string C_User_ID { get; set; }
        public DateTime C_DateTime { get; set; }
        public int? Reason_id { get; set; }
        public bool UsedInNotification { get; set; }
        public bool Changed { get; set; }
    }
}
