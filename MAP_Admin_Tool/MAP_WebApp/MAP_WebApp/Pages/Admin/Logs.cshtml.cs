using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;
using MAP_WebApp.Data;
using MAP_WebApp.Utils;

namespace MAP_WebApp.Pages.Admin
{
    [Authorize]
    public class LogsModel : BaseModel
    {
        public LogsModel(ToolDBContext context, IHttpContextAccessor accessor)
        {
            _context = context;
            _accessor = accessor;
        }

        public IActionResult OnGet()
        {
            if (!initPage(new int[] {1}))
                return new ForbidResult();

            return Page();
        }
        public async Task<IActionResult> OnPostLoadTable()
        {
            if (!initPage(new int[] { 1 }))
                return new ForbidResult();

            try
            {
                var draw = HttpContext.Request.Form["draw"].FirstOrDefault();

                var start = Request.Form["start"].FirstOrDefault();

                var length = Request.Form["length"].FirstOrDefault();

                var searchValue = Request.Form["search[value]"].FirstOrDefault();

                int pageSize = length != null ? Convert.ToInt32(length) : 0;

                int skip = start != null ? Convert.ToInt32(start) : 0;

                int recordsTotal = 0;

                var data = await _context.fn_AdminGetRequestLogsAsync(CurrentUser.Id);

                if (!string.IsNullOrEmpty(searchValue))
                    data = data.Where(m => m.IpAddress.ToUpper().Contains(searchValue.ToUpper())
                        || m.Path.ToUpper().Contains(searchValue.ToUpper())
                        || m.TraceIdent.ToUpper().Contains(searchValue.ToUpper())
                        || m.UserName.ToUpper().Contains(searchValue.ToUpper())
                        ).ToList();

                recordsTotal = data.Count();
                data = data.Skip(skip).Take(pageSize).ToList();

                return new JsonResult(new { draw = draw, recordsFiltered = recordsTotal, recordsTotal = recordsTotal, data = data });

            }
            catch (Exception)
            {
                throw;
            }
        }
    }
}
