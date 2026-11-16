using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.AspNetCore.Mvc.Rendering;
using Microsoft.EntityFrameworkCore;
using MAP_WebApp.Data;
using MAP_WebApp.Models.DB;
using MAP_WebApp.Utils;
using Microsoft.AspNetCore.Hosting;

namespace MAP_WebApp.Pages.Admin
{
    [Authorize]
    public class IndexModel : BaseModel
    {
        public IndexModel(ToolDBContext context, IHttpContextAccessor accessor, IWebHostEnvironment hostingEnv)
        {
            _context = context;
            _accessor = accessor;
            _hostingEnv = hostingEnv;
        }
        public List<SelectListItem> UserGroups = new List<SelectListItem>();

        public async Task<IActionResult> OnGet()
        {
            if (!initPage(new int[] { 1 }))
                return new ForbidResult();

            foreach (var option in await _context.N_UserGroups.ToListAsync())
                UserGroups.Add(new SelectListItem() { Value = option.Id.ToString(), Text = option.Name });

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

                var data = await _context.fn_AdminGetUserListAsync(CurrentUser.Id);
                
                if (!string.IsNullOrEmpty(searchValue))
                    data = data.Where(m => m.Name.ToUpper().Contains(searchValue.ToUpper())).ToList();

                recordsTotal = data.Count();
                data = data.Skip(skip).Take(pageSize).ToList();

                return new JsonResult(new { draw = draw, recordsFiltered = recordsTotal, recordsTotal = recordsTotal, data = data });

            }
            catch (Exception)
            {
                throw;
            }

        }

        public async Task<IActionResult> OnPostDelete(string Id)
        {
            if (!initPage(new int[] { 1 }))
                return new JsonResult(new { code = -1, msg = "Forbidden" });

            try
            {
                var result = await _context.usp_AdminDeleteUserAsync(CurrentUser.Id, Id);

                return new JsonResult(new { code = result.Code, msg = result.Msg });
            }
            catch (Exception ex)
            {
                if (InDevelopment)
                    return new JsonResult(new { code = -1, msg = ex.Message.ToString() });
                else
                    return new JsonResult(new { code = -1, msg = Const.ErrorMessage });
            }
        }

        public async Task<IActionResult> OnGetDetails(string Id)
        {
            if (!initPage(new int[] { 1}))
                return new JsonResult(new { code = -1, msg = "Forbidden" });

            try
            {
                var result = await _context.N_Users.Where(e => e.Id == Id).FirstOrDefaultAsync();

                return new JsonResult(new { code = 1, msg = result });
            }
            catch (Exception ex)
            {
                if (InDevelopment)
                    return new JsonResult(new { code = -1, msg = ex.Message.ToString() });
                else
                    return new JsonResult(new { code = -1, msg = Const.ErrorMessage });
            }
        }
        public async Task<IActionResult> OnPostSave(IFormCollection form)
        {
            if (!initPage(new int[] { 1 }))
                return new JsonResult(new { code = -1, msg = "Forbidden" });

            try
            {
                var UserId = form["EditUser_Id"].ToString();

                if (string.IsNullOrEmpty(UserId))
                {
                    var User = new N_Users()
                    {
                        Id = Guid.NewGuid().ToString().Replace("-", ""),
                        UserGroup_Id = int.Parse(form["edUserGroup"]),
                        LastActive = null,
                        Blocked = form["edBlocked"].ToString() == "on",
                        FirstName = form["edFirstName"].ToString(),
                        LastName = form["edLastName"].ToString(),
                        eMail = form["edeMail"].ToString(),
                        CreatedBy = CurrentUser.Id,
                        CreatedOn = DateTime.Now,
                        C_User_Id = CurrentUser.Id,
                        C_DateTime = DateTime.Now
                    };

                    _context.N_Users.Add(User);
                    await _context.SaveChangesAsync();

                    return new JsonResult(new { code = 1, msg = "" });
                }
                else
                {
                    var User = await _context.N_Users.FirstOrDefaultAsync(e => e.Id == UserId);

                    if (User == null)
                        return new JsonResult(new { code = -1, msg = "User not found!" });

                    User.FirstName = form["edFirstName"].ToString();
                    User.LastName = form["edLastName"].ToString();
                    User.eMail = form["edeMail"].ToString();
                    User.UserGroup_Id = int.Parse(form["edUserGroup"]);
                    User.Blocked = form["edBlocked"].ToString() == "on";
                    User.C_User_Id = CurrentUser.Id;
                    User.C_DateTime = DateTime.Now;

                    await _context.SaveChangesAsync();

                    return new JsonResult(new { code = 1, msg = "" });
                }
            }
            catch (Exception ex)
            {
                if (InDevelopment)
                    return new JsonResult(new { code = -1, msg = ex.Message.ToString() });
                else
                    return new JsonResult(new { code = -1, msg = Const.ErrorMessage });
            }
        }
    }
}
