using Microsoft.EntityFrameworkCore;
using System;

namespace MAP_WebApp.Models.DB
{
    [Keyless]
    public class fn_GetFisrtAndLastDayOfWeek
    {
        public DateTime FistDayOfWeek { get; set; }
        public DateTime LastDayOfWeek { get; set; }
    }
}
