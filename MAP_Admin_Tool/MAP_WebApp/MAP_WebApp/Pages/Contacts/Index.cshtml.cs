using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.AspNetCore.Mvc.Rendering;
using Microsoft.EntityFrameworkCore;
using MAP_WebApp.Data;
using MAP_WebApp.Utils;
using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Hosting;
using System.IO;
using Microsoft.Extensions.Options;
using MAP_WebApp.Models;

namespace MAP_WebApp.Pages.Contacts
{
    [Authorize]
    public class IndexModel : BaseModel
    {
        private readonly CustomSettings _customSettings;
        public IndexModel(ToolDBContext context, IOptions<CustomSettings> CustomSettings, IHttpContextAccessor accessor, IWebHostEnvironment hostingEnv)
        {
            _context = context;
            _accessor = accessor;
            _hostingEnv = hostingEnv;
            _customSettings = CustomSettings.Value;
        }
        public class InnerContacts
        {
            public int seller_id { get; set; }
            public string productCategory { get; set; }
            public int ContactType { get; set; }
            public string Value { get; set; }
        }

        public async Task<IActionResult> OnGet(string Id)
        {
            if (!initPage())
                return new ForbidResult();

            try
            {
               
            }
            catch (Exception) { 
                
            }


            return Page();
        }

        public async Task<IActionResult> OnPostContacts()
        {
            if (!initPage())
                return new JsonResult(new { code = -1, msg = "Forbidden" });

            try
            {
                var draw = HttpContext.Request.Form["draw"].FirstOrDefault();

                var start = Request.Form["start"].FirstOrDefault();

                var length = Request.Form["length"].FirstOrDefault();


                var searchValue = Request.Form["search[value]"].FirstOrDefault();

                int pageSize = length != null ? Convert.ToInt32(length) : 0;

                int skip = start != null ? Convert.ToInt32(start) : 0;

                int recordsTotal = 0;



                var data = await _context.fn_GetNotificationContactListAsync(
                        CurrentUser.Id,
                        TempData.Peek("fromDate") != null ? DateTime.Parse(TempData.Peek("fromDate").ToString()) : null,
                        TempData.Peek("policy")?.ToString(),
                        TempData.Peek("sellerType")?.ToString(),
                        TempData.Peek("sellerSubType")?.ToString(),
                        TempData.Peek("penaltyType")?.ToString(),
                        TempData.Peek("sellerName")?.ToString(),
                        TempData.Peek("hpApprovalStatus")?.ToString(),
                        TempData.Peek("productType")?.ToString(),
                        TempData.Peek("country") != null ? int.Parse(TempData.Peek("country").ToString()) : null
                    );

                recordsTotal = data.Count();

                data = data.Skip(skip).Take(pageSize).ToList();

                return new JsonResult(new { draw = draw, recordsFiltered = recordsTotal, recordsTotal = recordsTotal, data = data });
            }
            catch (Exception ex)
            {
                if (InDevelopment)
                    throw new Exception(ex.Message.ToString()); 
                else
                    throw new Exception("Аn error occurred while loading contacts!");
            }
        }

        public async Task<IActionResult> OnPostSaveContact([FromBody]InnerContacts data)
        {
            if (!initPage())
                return new ForbidResult();
            try
            {
                string country = TempData.Peek("country").ToString();
                var Contacts = await _context.fn_GetContactsBySellerAndCategoryAsync(data.seller_id, data.productCategory, 0, CurrentUser.Id, false, country.ToInt(0));
                foreach (var Contact in Contacts)
                {
                    var lcNotificationContact = _context.D_NotificationContact.Where(f => f.Id == Contact.Id).FirstOrDefault();
                    if (data.ContactType == 1)
                        lcNotificationContact.Email1 = data.Value == "" ? null : data.Value;
                    if (data.ContactType == 2)
                        lcNotificationContact.Email2 = data.Value == "" ? null : data.Value;
                    if (data.ContactType == 3)
                        lcNotificationContact.Email3 = data.Value == "" ? null : data.Value;
                    if (data.ContactType == 4)
                        lcNotificationContact.Email4 = data.Value == "" ? null : data.Value;
                    if (data.ContactType == 5)
                        lcNotificationContact.Email5 = data.Value == "" ? null : data.Value;
                    if (data.ContactType == 6)
                        lcNotificationContact.Email6 = data.Value == "" ? null : data.Value;
                    lcNotificationContact.C_User_id = CurrentUser.Id;
                    lcNotificationContact.C_DateTime = DateTime.Now;
                    lcNotificationContact.Changed = true;
                }

                await _context.SaveChangesAsync();

                return new JsonResult(new
                {
                    code = 1,
                    msg = ""
                });

            }
            catch (Exception ex)
            {
                if (InDevelopment)
                    return new JsonResult(new { code = -1, msg = ex.Message.ToString() });
                else
                    return new JsonResult(new { code = -1, msg = Const.ErrorMessage });
            }
        }

        public async Task<IActionResult> OnPostDownloadContacts()
        {
            if (!initPage())
                return new JsonResult(new { code = -1, msg = "Forbidden" });

            try
            {                
                string lcExportDate = DateTime.Now.ToString("[yyyy-MM-dd HH-mm-ss]");

                //var destPath = Path.Combine(_customSettings.StorageFolder, CurrentUser.Id);
                //if (!Directory.Exists(destPath))
                //    Directory.CreateDirectory(destPath);

                //destPath = Path.Combine(destPath, lcExportDate);
                //System.IO.File.Copy(Path.Combine(_customSettings.TemplateFolder, "7095B12C83A6411693679C62440EF8AF"), destPath);

                MemoryStream fileData = Utils.AzureAction.DownloadFromAzure(_customSettings, "7095B12C83A6411693679C62440EF8AF", true);

                var parameters = string.Format("@inUser_Id={0}^@inFromDate={1}^@inPolicy={2}^@inSellerType={3}^@inSellerSubType={4}^@inPenaltyType={5}^@inSellerName={6}^@inHPApprovalStatus={7}^@inProductType={8}^@inCountry_id={9}",
                    CurrentUser.Id, TempData.Peek("fromDate"), TempData.Peek("policy"), TempData.Peek("sellerType"), TempData.Peek("sellerSubType"), TempData.Peek("penaltyType"), TempData.Peek("sellerName"), TempData.Peek("hpApprovalStatus"), TempData.Peek("productType"), TempData.Peek("country"));

                var dstaSets = await _context.usp_GetDataSetsAsync("7095B12C83A6411693679C62440EF8AF", parameters);

                ExcelUtils.FillExcel(fileData, dstaSets);

                Utils.AzureAction.UploadToAzure(_customSettings, CurrentUser.Id.AppendURL(lcExportDate), fileData);

                return new JsonResult(new { code = 1, msg = lcExportDate });
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