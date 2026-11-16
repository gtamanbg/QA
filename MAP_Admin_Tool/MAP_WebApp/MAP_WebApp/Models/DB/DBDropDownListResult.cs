using Microsoft.EntityFrameworkCore;

namespace PM_WebApp.Models.DB
{
    [Keyless]
    public class DBDropDownListResult
    {
        public string Id { get; set; }
        public string Value { get; set; }
        public bool Selected { get; set; }
    }
}
