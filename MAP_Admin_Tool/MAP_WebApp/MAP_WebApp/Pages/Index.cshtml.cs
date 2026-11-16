using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.AspNetCore.Mvc.Rendering;
using Microsoft.EntityFrameworkCore;
using MAP_WebApp.Data;
using MAP_WebApp.Utils;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.IO;
using MAP_WebApp.Models;
using Microsoft.Extensions.Options;
using Microsoft.AspNetCore.Hosting;
using static System.Net.WebRequestMethods;
using MAP_WebApp.Models.DB;
using DocumentFormat.OpenXml.Office2010.Excel;
using DocumentFormat.OpenXml.Spreadsheet;


namespace MAP_WebApp.Pages
{
    [Authorize]
    public class IndexModel : BaseModel
    {
        private readonly CustomSettings _customSettings;
        public IndexModel(ToolDBContext context, IOptions<CustomSettings> CustomSettings, IHttpContextAccessor accessor, IWebHostEnvironment hostingEnv)
        {
            _context = context;
            _accessor = accessor;
            _customSettings = CustomSettings.Value;
            _hostingEnv = hostingEnv;
        }
        
        public List<SelectListItem> PolicyList = new List<SelectListItem>();
        public List<SelectListItem> SellerTypeList = new List<SelectListItem>();
        public List<SelectListItem> PenaltyTypeList = new List<SelectListItem>();
        public List<SelectListItem> SallerName = new List<SelectListItem>();
        public List<SelectListItem> ApprovalStatusList = new List<SelectListItem>();
        public List<SelectListItem> SellerSubTypeList = new List<SelectListItem>();
        public List<SelectListItem> ProductTypeList = new List<SelectListItem>();
        public List<SelectListItem> CountryList = new List<SelectListItem>();
        public string FilterFromDate = "";
        public string FilterToDate = "";
        public string FirstDayOfPreviousWeek = "";
        public string LastDayOfPreviousWeek = "";
        public string LastPage = "1";

        public fn_GetMapExecutionTrendsInfo MapExecTrends { get; set; }
        public string TitleUrl;
        public string TargetUrl;

        public class Notification
        {
            public int Id { get; set; }
            public int ApprovalStatus_id { get; set; }
            public string Notes { get; set; }
        }
        public async Task<IActionResult> OnGet()
        {
            if (!initPage())
                return new ForbidResult();

            try
            {
                var lcCountry_id = int.Parse(TempData["country"].ToStringDef("1"));

                var DropDownItems = await _context.fn_GetSCListDropDownFilterAsync("-1", CurrentUser.Id, lcCountry_id);
                PolicyList = DropDownItems.Where(e => e.Type == 0).OrderBy(e => e.OrderIndex).Select(e => new SelectListItem() { Value = e.Id.ToString(), Text = e.Value, Selected = (TempData["policy"] == null ? true : (TempData["policy"].ToString().Split(',').Contains(e.Id.ToString()) ? true : false))}).ToList();
                SellerTypeList = DropDownItems.Where(e => e.Type == 1).OrderBy(e => e.OrderIndex).Select(e => new SelectListItem() { Value = e.Id.ToString(), Text = e.Value, Selected = (TempData["sellerType"] == null ? true : (TempData["sellerType"].ToString().Split(',').Contains(e.Id.ToString()) ? true : false))}).ToList();
                PenaltyTypeList = DropDownItems.Where(e => e.Type == 2).OrderBy(e => e.OrderIndex).Select(e => new SelectListItem() { Value = e.Id.ToString(), Text = e.Value, Selected = (TempData["penaltyType"] == null ? true : (TempData["penaltyType"].ToString().Split(',').Contains(e.Id.ToString()) ? true : false))}).ToList();
                ApprovalStatusList = DropDownItems.Where(e => e.Type == 6).OrderBy(e => e.OrderIndex).Select(e => new SelectListItem() { Value = e.Id.ToString(), Text = e.Value, Selected = (TempData["hpApprovalStatus"] == null ? true : (TempData["hpApprovalStatus"].ToString().Split(',').Contains(e.Id.ToString()) ? true : false))}).ToList();
                SellerSubTypeList = DropDownItems.Where(e => e.Type == 7).OrderBy(e => e.OrderIndex).Select(e => new SelectListItem() { Value = e.Value, Text = e.Value, Selected = (TempData["sellerSubType"] == null ? true : (TempData["sellerSubType"].ToString().Split(',').Contains(e.Value) ? true : false))}).ToList();
                ProductTypeList = DropDownItems.Where(e => e.Type == 8).OrderBy(e => e.OrderIndex).Select(e => new SelectListItem() { Value = e.Id.ToString(), Text = e.Value, Selected = (TempData["productType"] == null ? true : (TempData["productType"].ToString().Split(',').Contains(e.Id.ToString()) ? true : false)) }).ToList();
                CountryList = DropDownItems.Where(e => e.Type == 10).OrderBy(e => e.OrderIndex).Select(e => new SelectListItem() { Value = e.Id.ToString(), Text = e.Value, Selected = (lcCountry_id == int.Parse(e.Id)) }).ToList();
            
                var lcDateFilterDefValue = await _context.fn_GetFisrtAndLastDayOfWeekAsync("");

                FirstDayOfPreviousWeek = lcDateFilterDefValue.FistDayOfWeek.ToString("yyyy-MM-dd");

                FilterFromDate = TempData["fromDate"] != null ? DateTime.Parse(TempData["fromDate"].ToString()).ToString("yyyy-MM-dd") : FirstDayOfPreviousWeek;
                if (TempData["LastPage"] != null && TempData["LastPage"].ToString() != "")
                    LastPage = TempData["LastPage"].ToString();


                var options = await _context.fn_GetSellerListAsync(
                        CurrentUser.Id,
                        FilterFromDate,
                        string.Join(",", PolicyList.Select(e => e.Value).ToArray()),
                        string.Join(",", SellerTypeList.Select(e => e.Value).ToArray()),
                        string.Join(",", SellerSubTypeList.Select(e => e.Value).ToArray()),
                        string.Join(",", PenaltyTypeList.Select(e => e.Value).ToArray()),
                        (TempData["sellerName"] == null ? "" : TempData["sellerName"].ToString()),
                        string.Join(",", ApprovalStatusList.Select(e => e.Value).ToArray()),
                        string.Join(",", ProductTypeList.Select(e => e.Value).ToArray()),
                        (TempData["sellerName"] == null ? 1 : 0),
                        lcCountry_id
                    );
                foreach (var option in options)
                    SallerName.Add(new SelectListItem() { Value = option.Id.ToString(), Text = option.Options, Selected = (TempData["sellerName"] == null ? true : (TempData["sellerName"].ToString().Split(',').Contains(option.Id.ToString()) ? true : false)) });
            }
            catch (Exception) {
                // to do
            }
            
            MapExecTrends = await _context.fn_GetMapExecutionTrendsInfoAsync(CurrentUser.Id);
            
            if (MapExecTrends != null)
            {
                TitleUrl = MapExecTrends.TitleUrl;
                TargetUrl = MapExecTrends.TargetUrl;
            }

            return Page();
        }

        public async Task<IActionResult> OnPostLoadTable(string country, string fromDate, string policy, string sellerType, string sellerSubType, string penaltyType, string sellerName, string hpApprovalStatus, string productType, string loadLastPage = "1")
        {
            if (!initPage())
                return new ForbidResult();

            try
            {
                var draw = HttpContext.Request.Form["draw"].FirstOrDefault();

                var start = Request.Form["start"].FirstOrDefault();
                if (loadLastPage == "1" && TempData["LastPage"] != null && TempData["LastPage"].ToString() != "")
                {
                    start = TempData["LastPage"].ToString();
                }

                var length = Request.Form["length"].FirstOrDefault();
                
                var searchValue = Request.Form["search[value]"].FirstOrDefault();

                int pageSize = length != null ? Convert.ToInt32(length) : 0;

                int skip = start != null ? Convert.ToInt32(start) : 0;

                int recordsTotal = 0;

                TempData["ApplyCustomFilter"] = "1";
                TempData["LastPage"] = start;
                TempData["fromDate"] = fromDate.ToString();
                TempData["country"] = country;
                TempData["policy"] = policy;
                TempData["sellerType"] = sellerType;
                TempData["sellerSubType"] = sellerSubType;
                TempData["penaltyType"] = penaltyType;
                TempData["sellerName"] = sellerName;
                TempData["hpApprovalStatus"] = hpApprovalStatus;
                TempData["productType"] = productType;

                var data = await _context.fn_GetNotificationListAsync(CurrentUser.Id, fromDate, policy, sellerType, sellerSubType, penaltyType, sellerName, hpApprovalStatus, productType, country);

                recordsTotal = data.Count();
                if (length != "-1")
                    data = data.Skip(skip).Take(pageSize).ToList();

                return new JsonResult(new { draw = draw, recordsFiltered = recordsTotal, recordsTotal = recordsTotal, data = data });

            }
            catch (Exception)
            {
                throw;
            }

        }
        public async Task<IActionResult> OnPostUpdateApprovalStatus(IFormCollection form)
        {
            if (!initPage())
                return new ForbidResult();

            try
            {
                string lcNotification_id = form["id"].ToString();
                string lcFieldName = "ApprovalStatus_id";
                string lcFieldvalue = form["ApprovalStatus_id"].ToString();

                var result = await _context.usp_UpdateNotificationHeaderAsync(CurrentUser.Id, lcNotification_id, lcFieldName, lcFieldvalue);

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
        public async Task<IActionResult> OnPostDownloadViolationDetail(IFormCollection form)
        {
            if (!initPage())
                return new JsonResult(new { code = -1, msg = "Forbidden" });

            try
            {
                string fromDate = form["fromDate"];
                string policy = form["policy"];
                string sellerType = form["sellerType"];
                string sellerSubType = form["sellerSubType"];
                string penaltyType = form["penaltyType"];
                string sellerName = form["sellerName"];
                string hpApprovalStatus = form["hpApprovalStatus"];
                string productType = form["productType"];
                string country_id = form["country"];

                string lcExportDate = DateTime.Now.ToString("[yyyy-MM-dd HH-mm-ss]");

                //var destPath = Path.Combine(_customSettings.StorageFolder, CurrentUser.Id);
                //if (!Directory.Exists(destPath))
                //    Directory.CreateDirectory(destPath);

                //destPath = Path.Combine(destPath, lcExportDate);
                //System.IO.File.Copy(Path.Combine(_customSettings.TemplateFolder, "BB8B81C380124CA08FC539333A74F99E"), destPath);

                MemoryStream fileData = Utils.AzureAction.DownloadFromAzure(_customSettings, "BB8B81C380124CA08FC539333A74F99E", true);

                var parameters = string.Format("@inUser_Id={0}^@inFromDate={1}^@inPolicy={2}^@inSellerType={3}^@inSellerSubType={4}^@inPenaltyType={5}^@inSellerName={6}^@inHPApprovalStatus={7}^@inProductType={8}^@inCountry_id={9}",
                    CurrentUser.Id, fromDate, policy, sellerType, sellerSubType, penaltyType, sellerName, hpApprovalStatus, productType, country_id);

                var dstaSets = await _context.usp_GetDataSetsAsync("BB8B81C380124CA08FC539333A74F99E", parameters);

                //ExcelUtils.FillExcel(destPath, dstaSets);
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
        public async Task<IActionResult> OnPostUpdateNotes(IFormCollection form)
        {
            if (!initPage())
                return new ForbidResult();

            try
            {
                string lcNotification_id = form["id"].ToString();
                string lcFieldName = "Notes";
                string lcFieldvalue = form["Notes"].ToString();

                var result = await _context.usp_UpdateNotificationHeaderAsync(CurrentUser.Id, lcNotification_id, lcFieldName, lcFieldvalue);

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
        public async Task<IActionResult> OnPostSaveNotification([FromBody]List<Notification> inData)
        {
            if (!initPage())
                return new ForbidResult();
            try
            {
                string lcChangesNotification = null;
                foreach(Notification data in inData)
                {
                    var lcNotification = _context.D_Notification.Where(f => f.Id == data.Id).FirstOrDefault();
                    bool lcASChanged = lcNotification.ApprovalStatus_id != data.ApprovalStatus_id;
                    lcNotification.ApprovalStatus_id = data.ApprovalStatus_id;
                    lcNotification.Notes = data.Notes == "" ? null : data.Notes.st();
                    lcNotification.C_User_ID = CurrentUser.Id;
                    lcNotification.C_DateTime = DateTime.Now;
                    lcNotification.Changed =true;

                    if (!lcASChanged)
                    {
                        var notifications = await _context.fn_GetNotificaitonDetailsReplacementsAsync(data.Id.ToString(), CurrentUser.Id);
                        if (_context.D_NotificationDetail.Where(f => f.Master_id == data.Id && f.ApprovalStatus_id != 4).Count() < lcNotification.ThresholdValue &&
                            (
                                (lcNotification.Penalty_id == 1) ||
                                (lcNotification.Penalty_id != 1 && notifications?.Count() == 0)
                            )
                        )
                            lcNotification.ApprovalStatus_id = 4;

                    }

                    lcChangesNotification += data.Id.ToString() + ";";
                }
                
                await _context.SaveChangesAsync();
                var result = await _context.usp_CheckNotificationThreshHoldAsync(lcChangesNotification, CurrentUser.Id);

                return new JsonResult(new
                {
                    code = result.Code,
                    msg = result.Msg
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
        public async Task<IActionResult> OnPostSellers(string country, string fromDate, string policy, string sellerType, string sellerSubType, string penaltyType, string sellerName, string hpApprovalStatus, string productType, string allSellerList)
        {
            if (!initPage())
                return new JsonResult(new { code = -1, msg = "Forbidden" });

            try
            {
                int allSellerSelected = (sellerName == allSellerList ? 1 : 0);
                if (TempData["LastAllsellerSelected"] == null)
                    TempData["LastAllsellerSelected"] = 1;
                if (sellerName != null)
                {
                    TempData["LastsellerName"] = sellerName;
                    TempData["LastAllsellerSelected"] = (sellerName == allSellerList ? 1 : 0);
                }
                else if(TempData["LastsellerName"] != null)
                    sellerName = TempData["LastsellerName"].ToString();
                allSellerSelected = (allSellerList == null ? int.Parse(TempData["LastAllsellerSelected"].ToString()) : allSellerSelected);

                var options = (await _context.fn_GetSellerListAsync(CurrentUser.Id, fromDate, policy,
                    sellerType, sellerSubType, penaltyType, sellerName, hpApprovalStatus, productType,
                    allSellerSelected, int.Parse(country)))
                    .Select(e => new { e.Id, e.Options, e.IsSelected });
                    
                return new JsonResult(new { code = 1, msg = options });
            }
            catch (Exception ex)
            {
                if (InDevelopment)
                    return new JsonResult(new { code = -1, msg = ex.Message.ToString() });
                else
                    return new JsonResult(new { code = -1, msg = Const.ErrorMessage });
            }
        }
        public async Task<IActionResult> OnPostCountry(string country)
        {
            if (!initPage())
                return new JsonResult(new { code = -1, msg = "Forbidden" });

            try
            {
                var DropDownItems = await _context.fn_GetSCListDropDownFilterAsync("-1", CurrentUser.Id, int.Parse(country));

                return new JsonResult(new { code = 1, msg = DropDownItems });
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