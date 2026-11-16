using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using MAP_WebApp.Data;
using MAP_WebApp.Models;
using MAP_WebApp.Utils;
using System;

namespace MAP_WebApp.Pages
{
    [Authorize]
    public class DownloadModel : BaseModel
    {
        private readonly CustomSettings _customSettings;
        public DownloadModel(ToolDBContext context, IOptions<CustomSettings> CustomSettings, IHttpContextAccessor accessor)
        {
            _context = context;
            _accessor = accessor;
            _customSettings = CustomSettings.Value;
        }

        public IActionResult OnGet(string Id)
        {
            if (!initPage())
                return new ForbidResult();

            string fileInfo = Id+".xlsx";// "ViolationsDetail.xlsx";

            //var destPath = Path.Combine(_customSettings.StorageFolder, CurrentUser.Id, Id);
            //Stream stream = System.IO.File.Open(destPath, FileMode.Open);
            Stream stream;
            try
            {
                stream = AzureAction.DownloadFromAzure(_customSettings, CurrentUser.Id.AppendURL(Id));
            }
            catch (Exception)
            {
                return NotFound();
            }


            if (stream == null)
                return new NotFoundResult();

            return File(stream, "application/octet-stream", fileInfo);
        }
    }
}