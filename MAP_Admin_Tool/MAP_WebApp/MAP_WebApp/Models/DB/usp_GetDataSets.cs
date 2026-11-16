using Microsoft.EntityFrameworkCore;

namespace MAP_WebApp.Models.DB
{
    [Keyless]
    public class usp_GetDataSets
    {
        public byte DSIndex { get; set; }
        public string SheetName { get; set; }
        public string Data { get; set; }
    }
}
