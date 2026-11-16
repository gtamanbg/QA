using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using MAP_WebApp.Data;
using MAP_WebApp.Utils;

namespace MAP_WebApp.Pages
{
    [Authorize]
    public class SupportModel : BaseModel
    {
        public SupportModel(ToolDBContext context, IHttpContextAccessor accessor)
        {
            _context = context;
            _accessor = accessor;
        }

        public async Task<IActionResult> OnGet()
        {
            if (!initPage())
                return new ForbidResult();

            return Page();
        }
    }
}