using Microsoft.EntityFrameworkCore;

namespace MAP_WebApp.Models.DB
{
    [Keyless]
    public class fn_GetMapExecutionTrendsInfo
    {
        public string TitleUrl { get; set; }

        public string TargetUrl { get; set; }
    }
}
