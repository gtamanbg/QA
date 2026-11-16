using Microsoft.EntityFrameworkCore;

namespace MAP_WebApp.Models.DB
{
    [Keyless]
    public class fn_GetNotificationDetailChange
    {
        public decimal Alternative_Penalty { get; set; }
        public decimal Alternative_Percent_Amount { get; set; }
        public decimal AdjustedPenalty { get; set; }
        public int HeaderApprovalStatus_id { get; set; }
    }
}
