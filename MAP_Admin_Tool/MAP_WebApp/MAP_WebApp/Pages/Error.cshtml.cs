using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using MAP_WebApp.Data;
using MAP_WebApp.Utils;

namespace MAP_WebApp.Pages
{
    [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
    public class ErrorModel : BaseModel
    {
        public ErrorModel(ToolDBContext context, IHttpContextAccessor accessor)
        {
            _context = context;
            _accessor = accessor;
        }
        public string RequestId { get; set; }
        public int Code { get; set; }
        public string Message { get; set; }

        public bool ShowRequestId => !string.IsNullOrEmpty(RequestId);

        public void OnGet(int code)
        {
            initPage();

            Code = code;
            switch (Code)
            {
                case 404:
                    Message = "Resource not found. Please contact your administrator for more information.";
                    break;
                case 403:
                    Message = "Access Denied. You dont have permitions to open that page. Please contact your administrator for more information.";
                    break;
                default:
                    Message = "An error occurred while processing your request. Please contact your administrator for more information.";
                    break;
            }
            
            RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier;
        }
    }
}
