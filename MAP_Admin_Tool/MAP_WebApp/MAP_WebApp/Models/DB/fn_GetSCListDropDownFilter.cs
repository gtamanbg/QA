using Microsoft.EntityFrameworkCore;
using PM_WebApp.Models.DB;

namespace MAP_WebApp.Models.DB
{
    [Keyless]
    public class fn_GetSCListDropDownFilter : DBDropDownListResult
    {
        public int OrderIndex { get; set; }
        public int Type { get; set; }
    }
}
