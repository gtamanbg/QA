using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using MAP_WebApp.Utils;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace MAP_WebApp.Pages.Account
{
    public class LoggedOutModel : PageModel
    {
        public void OnGet()
        {
            var r = HttpContext.Session.GetString("r");
            ViewData["r"] = r.DecodeBase64();
        }
    }
}
