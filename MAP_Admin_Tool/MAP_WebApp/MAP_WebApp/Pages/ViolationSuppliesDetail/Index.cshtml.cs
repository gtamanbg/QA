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
using MAP_WebApp.Models.DB;
using Microsoft.AspNetCore.Hosting;

namespace MAP_WebApp.Pages.ViolationSuppliesDetail
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

        public fn_GetNotificaitonInfo NotificationInfo { get; set; }
        public List<SelectListItem> ApprovalStatusList = new List<SelectListItem>();
        public List<SelectListItem> LineApprovalStatusList = new List<SelectListItem>();
        public List<SelectListItem> StateList = new List<SelectListItem>();
        public class Violation
        {
            public int Id { get; set; }
            public string Contact1 { get; set; }
            public string Contact2 { get; set; }
            public string Contact3 { get; set; }
            public string Contact4 { get; set; }
            public string Contact5 { get; set; }
            public string Contact6 { get; set; }
            public string Email1 { get; set; }
            public string Email2 { get; set; }
            public string Email3 { get; set; }
            public string Email4 { get; set; }
            public string Email5 { get; set; }
            public string Email6 { get; set; }
            public string Address { get; set; }
            public string City { get; set; }
            public int? State_id { get; set; }
            public string Zip { get; set; }
            public int ApprovalStatus_id { get; set; }
            public string Notes { get; set; }
            public int VisibleForHP { get; set; }
            public string SuppliesAlternativePercent { get; set; }
            public List<ViolationDetails> Details { get; set; }
        }

        public class ViolationDetails
        {
            public string Id { get; set; }
            public int ApprovalStatus_id { get; set; }
            public string Alternative_Percent_Amount { get; set; }
            public string Notes { get; set; }
            public int? Reason_id { get; set; }
            public int? HPReason_id { get; set; }
            public bool Changed { get; set; }
        }
        public class ReplacementDetail
        {
            public string Id { get; set; }
            public int Notification_id { get; set; }
            public bool Checked { get; set; }
            public int ApprovalStatus_id { get; set; }
            public int? Reason_id { get; set; }
        }
        public async Task<IActionResult> OnGet(string Id)
        {
            if (!initPage())
                return new ForbidResult();

            try
            {
                NotificationInfo = await _context.fn_GetNotificaitonInfoAsync(Id, CurrentUser.Id);

                if (NotificationInfo == null)
                    return Redirect("/");
                //return new NotFoundResult();

                foreach (var option in await _context.fn_GetSCListDropDownFilterAsync("3", CurrentUser.Id, NotificationInfo.Country_id))
                    ApprovalStatusList.Add(new SelectListItem() { Value = option.Id.ToString(), Text = option.Value, Selected = (NotificationInfo.Approval_Status_id.ToString() == option.Id? true : false) });
                foreach (var option in await _context.fn_GetSCListDropDownFilterAsync("5", CurrentUser.Id, NotificationInfo.Country_id))
                    LineApprovalStatusList.Add(new SelectListItem() { Value = option.Id.ToString(), Text = option.Value, Selected = (NotificationInfo.Approval_Status_id.ToString() == option.Id ? true : false) });
                foreach (var option in await _context.fn_GetSCListDropDownFilterAsync("9", CurrentUser.Id, NotificationInfo.Country_id))
                    StateList.Add(new SelectListItem() { Value = option.Id.ToString(), Text = option.Value, Selected = false });

            }
            catch (Exception) {

            }


            return Page();
        }

        public async Task<IActionResult> OnPostLoadDetails(string id)
        {
            if (!initPage())
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

                var data = await _context.fn_GetNotificaitonDetailsAsync(id, CurrentUser.Id);

                recordsTotal = data.Count();

                data = data.Skip(skip).Take(pageSize).ToList();

                return new JsonResult(new { draw = draw, recordsFiltered = recordsTotal, recordsTotal = recordsTotal, data = data });

            }
            catch (Exception ex)
            {
                if (InDevelopment)
                    return new JsonResult(new { code = -1, msg = ex.Message.ToString() });
                else
                    return new JsonResult(new { code = -1, msg = Const.ErrorMessage });
            }
        }
               
        public async Task<IActionResult> OnPostSaveNotification([FromBody]Violation data)
        {
            if (!initPage())
                return new ForbidResult();
            try
            {
                var lcNotification = _context.D_Notification.Where(f => f.Id == data.Id).FirstOrDefault();
                //HP Users can't change Approval status of is void or on hold
                if (CurrentUser.UserGroup_Id == 4 && 
                    new List<int?> {3,4}.Contains(lcNotification.ApprovalStatus_id) &&
                    lcNotification.ApprovalStatus_id != data.ApprovalStatus_id)
                    return new JsonResult(new { code = -1, msg = "Please contact a Site Admin to change Approval Status!" });
                bool lcASChanged = lcNotification.ApprovalStatus_id != data.ApprovalStatus_id;

                decimal? SuppliesAlternativePercent = null;
                if (data.SuppliesAlternativePercent != "")
                    SuppliesAlternativePercent = decimal.Parse(data.SuppliesAlternativePercent);

                lcNotification.Changed = true;
                lcNotification.ApprovalStatus_id = data.ApprovalStatus_id;
                lcNotification.Notes = data.Notes == "" ? null : data.Notes.st();
                lcNotification.SuppliesAlternativePercent = SuppliesAlternativePercent;
                lcNotification.C_User_ID = CurrentUser.Id;
                lcNotification.C_DateTime = DateTime.Now;

                if (new int[] { 1, 2 }.Contains(CurrentUser.UserGroup_Id) && data.VisibleForHP != -1)
                    lcNotification.VisibleForHP = data.VisibleForHP;

                var contactChangeCheck = _context.D_NotificationContact.Where(f => f.Id == lcNotification.Contacts_id).FirstOrDefault();
                if (contactChangeCheck.Contact1 != (data.Contact1 == "" ? null : data.Contact1.st()) ||
                    contactChangeCheck.Contact2 != (data.Contact2 == "" ? null : data.Contact2.st()) ||
                    contactChangeCheck.Contact3 != (data.Contact3 == "" ? null : data.Contact3.st()) ||
                    contactChangeCheck.Contact4 != (data.Contact4 == "" ? null : data.Contact4.st()) ||
                    contactChangeCheck.Contact5 != (data.Contact5 == "" ? null : data.Contact5.st()) ||
                    contactChangeCheck.Contact6 != (data.Contact6 == "" ? null : data.Contact6.st()) ||
                    contactChangeCheck.Address != (data.Address == "" ? null : data.Address.st()) ||
                    contactChangeCheck.City != (data.City == "" ? null : data.City.st()) ||
                    contactChangeCheck.State_id != data.State_id ||
                    contactChangeCheck.Zip != (data.Zip == "" ? null : data.Zip.st())
                   )
                {
                    var contacts = await _context.fn_GetContactsBySellerAndCategoryAsync(0, "", lcNotification.Contacts_id, CurrentUser.Id, true, 0);
                    foreach (var Contact in contacts)
                    {
                        var lcNotificationContact = _context.D_NotificationContact.Where(f => f.Id == Contact.Id).FirstOrDefault();
                        lcNotificationContact.Contact1 = data.Contact1 == "" ? null : data.Contact1.st();
                        lcNotificationContact.Contact2 = data.Contact2 == "" ? null : data.Contact2.st();
                        lcNotificationContact.Contact3 = data.Contact3 == "" ? null : data.Contact3.st();
                        lcNotificationContact.Contact4 = data.Contact4 == "" ? null : data.Contact4.st();
                        lcNotificationContact.Contact5 = data.Contact5 == "" ? null : data.Contact5.st();
                        lcNotificationContact.Contact6 = data.Contact6 == "" ? null : data.Contact6.st();
                        lcNotificationContact.Address = data.Address == "" ? null : data.Address.st();
                        lcNotificationContact.City = data.City == "" ? null : data.City.st();
                        lcNotificationContact.State_id = data.State_id;
                        lcNotificationContact.Zip = data.Zip == "" ? null : data.Zip.st();
                        lcNotificationContact.C_User_id = CurrentUser.Id;
                        lcNotificationContact.C_DateTime = DateTime.Now;
                        lcNotificationContact.Changed = true;
                    }
                }

                if (contactChangeCheck.Email1 != (data.Email1 == "" ? null : data.Email1.st()) ||
                    contactChangeCheck.Email2 != (data.Email2 == "" ? null : data.Email2.st()) ||
                    contactChangeCheck.Email3 != (data.Email3 == "" ? null : data.Email3.st()) ||
                    contactChangeCheck.Email4 != (data.Email4 == "" ? null : data.Email4.st()) ||
                    contactChangeCheck.Email5 != (data.Email5 == "" ? null : data.Email5.st()) ||
                    contactChangeCheck.Email6 != (data.Email6 == "" ? null : data.Email6.st())
                   )
                {
                    var contacts = await _context.fn_GetContactsBySellerAndCategoryAsync(0, "", lcNotification.Contacts_id, CurrentUser.Id, false, 0);
                    foreach (var Contact in contacts)
                    {
                        var lcNotificationContact = _context.D_NotificationContact.Where(f => f.Id == Contact.Id).FirstOrDefault();
                        lcNotificationContact.Email1 = data.Email1 == "" ? null : data.Email1.st();
                        lcNotificationContact.Email2 = data.Email2 == "" ? null : data.Email2.st();
                        lcNotificationContact.Email3 = data.Email3 == "" ? null : data.Email3.st();
                        lcNotificationContact.Email4 = data.Email4 == "" ? null : data.Email4.st();
                        lcNotificationContact.Email5 = data.Email5 == "" ? null : data.Email5.st();
                        lcNotificationContact.Email6 = data.Email6 == "" ? null : data.Email6.st();
                        lcNotificationContact.C_User_id = CurrentUser.Id;
                        lcNotificationContact.C_DateTime = DateTime.Now;
                        lcNotificationContact.Changed = true;
                    }
                }

                foreach (ViolationDetails lcSP in data.Details.Where(e => e.Changed))
                {
                    var lcNotificationDetail = _context.D_NotificationDetail.Where(f => f.Id == lcSP.Id).FirstOrDefault();
                    lcNotificationDetail.ApprovalStatus_id = lcSP.ApprovalStatus_id;
                    lcNotificationDetail.Notes = lcSP.Notes == "" ? null : lcSP.Notes.st();
                    if (CurrentUser.UserGroup_Id != 4)
                        lcNotificationDetail.Reason_id = lcSP.Reason_id;
                    if (CurrentUser.UserGroup_Id != 3)
                        lcNotificationDetail.HPReason_id = lcSP.HPReason_id;
                    lcNotificationDetail.C_User_ID = CurrentUser.Id;
                    lcNotificationDetail.C_DateTime = DateTime.Now;
                    lcNotificationDetail.Changed = true;
                }
                await _context.SaveChangesAsync();
                var result = await _context.usp_CheckNotificationThreshHoldAsync(data.Id.ToString(), CurrentUser.Id);

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
        
        public async Task<IActionResult> OnGetReason(string Id, string ReasonType)
        {
            if (!initPage())
                return new JsonResult(new { code = -1, msg = "Forbidden" });

            try
            {
                var options = (await _context.fn_GetReasonsAsync(Id, ReasonType))
                    .Select(e => new { e.Id, e.Options })
                    .ToList();

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
        public async Task<IActionResult> OnPostLoadReplacements(string id)
        {
            if (!initPage())
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

                var data = (await _context.fn_GetNotificaitonDetailsReplacementsAsync(id, CurrentUser.Id))
                    .OrderBy(e => e.Ranking)
                    .ToList();

                recordsTotal = data.Count();

                if (length != "-1")
                    data = data.Skip(skip).Take(pageSize).ToList();

                return new JsonResult(new { draw = draw, recordsFiltered = recordsTotal, recordsTotal = recordsTotal, data = data });

            }
            catch (Exception ex)
            {
                if (InDevelopment)
                    return new JsonResult(new { code = -1, msg = ex.Message.ToString() });
                else
                    return new JsonResult(new { code = -1, msg = Const.ErrorMessage });
            }
        }
        public async Task<IActionResult> OnPostSaveReplacement([FromBody]List<ReplacementDetail> data)
        {
            if (!initPage())
                return new ForbidResult();
            try
            {
                int lcCode = 1;
                string lcMsg = null;
                foreach (ReplacementDetail lcSP in data)
                {
                    var lcReplacements = _context.D_NotificationDetailReplacements.Where(f => f.Id == lcSP.Id).FirstOrDefault();

                    lcReplacements.ReplacementApprovalStatus_Id = lcSP.ApprovalStatus_id;
                    lcReplacements.Reason_id = lcSP.Reason_id;
                    lcReplacements.C_User_ID = CurrentUser.Id;
                    lcReplacements.C_DateTime = DateTime.Now;
                    lcReplacements.Changed = true;

                    if (lcSP.Checked)
                    {
                        lcReplacements.UsedInNotification = true;
                        var result = await _context.usp_AddReplacementAsync(lcSP.Id, lcSP.Notification_id, CurrentUser.Id);

                        if (result.Code == -1)
                        {
                            return new JsonResult(new { code = result.Code, msg = result.Msg });
                        }
                    }
                }

                await _context.SaveChangesAsync();
                if (data.Count() > 0)
                {
                    var checkResult = await _context.usp_CheckNotificationThreshHoldAsync(data.FirstOrDefault()?.Notification_id.ToString(), CurrentUser.Id);

                    if (checkResult.Code == -1)
                    {
                        return new JsonResult(new { code = checkResult.Code, msg = checkResult.Msg });
                    }
                    else
                    {
                        lcCode = checkResult.Code;
                        lcMsg = checkResult.Msg;
                    }
                }

                return new JsonResult(new { code = lcCode, msg = lcMsg });

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