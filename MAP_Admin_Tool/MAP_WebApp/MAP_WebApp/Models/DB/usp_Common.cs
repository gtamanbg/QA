using Microsoft.EntityFrameworkCore;

namespace MAP_WebApp.Models.DB
{
    [Keyless]
    public class usp_Common
    {
        public int Code { get; set; }
        public string Msg { get; set; }
    }
}
