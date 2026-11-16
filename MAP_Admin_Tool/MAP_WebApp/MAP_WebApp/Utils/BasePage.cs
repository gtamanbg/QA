using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;
using MAP_WebApp.Data;
using MAP_WebApp.Models.DB;
using System.Linq;
using Microsoft.AspNetCore.Hosting;
using MAP_WebApp.Models;
using Microsoft.Extensions.Options;
using Microsoft.Extensions.DependencyInjection;

namespace MAP_WebApp.Utils
{
    public partial class BaseModel : PageModel
    {
        protected ToolDBContext _context;
        protected IHttpContextAccessor _accessor;
        protected X_CurrentUser CurrentUser;
        protected IWebHostEnvironment _hostingEnv;
        protected bool InDevelopment;

        public bool initPage(int[] UserGroup_Id = null)
        {
            LogUserRequest();
            UserGroup_Id = UserGroup_Id ?? new int[0];

            if (CurrentUser == null || CurrentUser.Blocked)
                return false;

            if (UserGroup_Id.Length > 0 && !UserGroup_Id.Contains(CurrentUser.UserGroup_Id))
                return false;

            ViewData["UserGroup_Id"] = CurrentUser.UserGroup_Id;

            return true;
        }

        private void LogUserRequest()
        {
            InDevelopment = _hostingEnv?.EnvironmentName?.ToLower() == "development";
            if (_context != null && User.Identity.IsAuthenticated) { 
                var openIdFields = _accessor.HttpContext.RequestServices.GetService<IOptions<OpenIdFields>>().Value;

                var OktaUserName = User.FindFirst(openIdFields.EmailField).Value;

                CurrentUser = _context.usp_LogUserRequestAsync(
                    User.FindFirst(openIdFields.IdField).Value,
                    OktaUserName,
                    _accessor.HttpContext?.Request?.Path.ToString(),
                    _accessor.HttpContext?.Request?.QueryString.ToString(),
                    _accessor.HttpContext.Request?.Headers["User-Agent"].ToString(),
                    _accessor.HttpContext?.Connection?.RemoteIpAddress?.ToString(),
                    _accessor.HttpContext?.Request.HttpContext.TraceIdentifier.ToString()
                )?.Result;
            }
            else
                CurrentUser = null;
        }
    }
}