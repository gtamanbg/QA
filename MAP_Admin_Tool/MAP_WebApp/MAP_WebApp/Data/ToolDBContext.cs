using Microsoft.EntityFrameworkCore;
using MAP_WebApp.Models.DB;
using System.Linq;
using System.Threading.Tasks;
using System.Collections.Generic;
using System;

namespace MAP_WebApp.Data
{
    public class ToolDBContext : DbContext
    {
        public ToolDBContext(DbContextOptions<ToolDBContext> options)
        : base(options)
        {
            
        }

        #region Tables
        public DbSet<N_Users> N_Users { get; set; }
        public DbSet<N_UserGroups> N_UserGroups { get; set; }
        public DbSet<D_NotificationDetail> D_NotificationDetail { get; set; }
        public DbSet<D_NotificationDetailReplacements> D_NotificationDetailReplacements { get; set; }
        public DbSet<D_Notification> D_Notification { get; set; }
        public DbSet<D_NotificationContact> D_NotificationContact { get; set; }
        #endregion

        #region Functions
        private DbSet<fn_AdminGetUserList> fn_AdminGetUserList { get; set; }
        private DbSet<fn_AdminGetRequestLogs> fn_AdminGetRequestLogs { get; set; }
        private DbSet<fn_GetNotificationList> fn_GetNotificationList { get; set; }
        private DbSet<fn_GetSCListDropDownFilter> fn_GetSCListDropDownFilter { get; set; }
        private DbSet<fn_GetNotificaitonInfo> fn_GetNotificaitonInfo { get; set; }
        private DbSet<fn_GetNotificaitonDetails> fn_GetNotificaitonDetails { get; set; }
        private DbSet<fn_GetNotificationDetailChange> fn_GetNotificationDetailChange { get; set; }
        private DbSet<fn_GetFisrtAndLastDayOfWeek> fn_GetFisrtAndLastDayOfWeek { get; set; }
        private DbSet<fn_GetReasons> fn_GetReasons { get; set; }
        private DbSet<fn_GetNotificaitonDetailsReplacements> fn_GetNotificaitonDetailsReplacements { get; set; }
        private DbSet<fn_GetNotificationContactList> fn_GetNotificationContactList { get; set; }
        private DbSet<fn_GetSellerList> fn_GetSellerList { get; set; }
        private DbSet<fn_GetContactsBySellerAndCategory> fn_GetContactsBySellerAndCategory { get; set; }

        private DbSet<usp_Common> usp_Common { get; set; }
        private DbSet<usp_GetDataSets> usp_GetDataSets { get; set; }

        private DbSet<X_CurrentUser> X_CurrentUser { get; set; }

        private DbSet<fn_GetMapExecutionTrendsInfo> fn_GetMapExecutionTrendsInfo { get; set; }
        #endregion

        #region Methods
        public async Task<List<fn_AdminGetUserList>> fn_AdminGetUserListAsync(string userId)
        {
            var result = await fn_AdminGetUserList.FromSqlRaw("SELECT * FROM fn_AdminGetUserList({0})", userId).OrderBy(e => e.Name).AsNoTracking().ToListAsync();
            return result;
        }
        public async Task<List<fn_AdminGetRequestLogs>> fn_AdminGetRequestLogsAsync(string userId)
        {
            var result = await fn_AdminGetRequestLogs.FromSqlRaw("SELECT * FROM fn_AdminGetRequestLogs({0})", userId).OrderByDescending(e => e.Id).AsNoTracking().ToListAsync();
            return result;
        }
        public async Task<List<fn_GetNotificationContactList>> fn_GetNotificationContactListAsync(string userId,DateTime? fromDate,
            string policy,string sellerType,string sellerSubType,string penaltyType,string sellerName,string hpApprovalStatus,
            string productType,int? countryId)
        {

            var result = await fn_GetNotificationContactList
                .FromSqlRaw(
                    "SELECT * FROM fn_GetNotificationContactList({0},{1},{2},{3},{4},{5},{6},{7},{8},{9})",
                    userId,
                    fromDate,
                    policy,
                    sellerType,
                    sellerSubType,
                    penaltyType,
                    sellerName,
                    hpApprovalStatus,
                    productType,
                    countryId
                )
                .OrderBy(e => e.Id)
                .AsNoTracking()
                .ToListAsync();
            return result;
        }
        public async Task<List<fn_GetContactsBySellerAndCategory>> fn_GetContactsBySellerAndCategoryAsync(int sellerId,
            string productCategory,int? contactId,string userId,bool internalExternal,int countryId)
        {
            var result = await fn_GetContactsBySellerAndCategory
                .FromSqlRaw(
                    "SELECT * FROM fn_GetContactsBySellerAndCategory({0},{1},{2},{3},{4},{5})", 
                    sellerId,
                    productCategory,
                    contactId,
                    userId,
                    internalExternal,
                    countryId
                )
                .AsNoTracking()
                .ToListAsync();
            return result;
        }
        public async Task<List<fn_GetSCListDropDownFilter>> fn_GetSCListDropDownFilterAsync(string filterType, string userId, int countryId)
        {
            var result = await fn_GetSCListDropDownFilter
                .FromSqlRaw("SELECT * FROM fn_GetSCListDropDownFilter({0},{1},{2})", filterType, userId, countryId)
                .OrderBy(e => e.OrderIndex)
                .AsNoTracking()
                .ToListAsync();
            return result;
        }
        public async Task<fn_GetFisrtAndLastDayOfWeek> fn_GetFisrtAndLastDayOfWeekAsync(string date)
        {
            var result = await fn_GetFisrtAndLastDayOfWeek
                .FromSqlRaw("SELECT * FROM fn_GetFisrtAndLastDayOfWeek({0})", date)
                .AsNoTracking()
                .ToListAsync();
            return result.FirstOrDefault();
        }
        public async Task<List<fn_GetSellerList>> fn_GetSellerListAsync(string userId,string fromDate,string policy,string sellerType,
            string sellerSubType,string penaltyType,string sellerName,string ApprovalStatus,string productType,
            int allSellerSelected,int countryId)
        {
            var result = await fn_GetSellerList
                .FromSqlRaw(
                    "SELECT * FROM fn_GetSellerList({0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10})",
                    userId,
                    fromDate,
                    policy,
                    sellerType,
                    sellerSubType,
                    penaltyType,
                    sellerName,
                    ApprovalStatus,
                    productType,
                    allSellerSelected,
                    countryId
                 )
                .OrderBy(e => e.Id)
                .AsNoTracking()
                .ToListAsync();
            return result;
        }
        public async Task<List<fn_GetNotificationList>> fn_GetNotificationListAsync(string userId, string fromDate,
            string policy, string sellerType, string sellerSubType, string penaltyType, string sellerName,
            string hpApprovalStatus, string productType, string country)
        {
            var result = await fn_GetNotificationList
                .FromSqlRaw(
                    "SELECT * FROM fn_GetNotificationList({0},{1},{2},{3},{4},{5},{6},{7},{8},{9})",
                    userId, 
                    fromDate, 
                    policy, 
                    sellerType, 
                    sellerSubType, 
                    penaltyType, 
                    sellerName, 
                    hpApprovalStatus, 
                    productType, 
                    country
                )
                .OrderBy(e => e.ApprovalStatusForOrder)
                .ThenBy(e => e.FinStatusForOrder)
                .ThenBy(e => e.Policy)
                .ThenBy(e => e.PenaltyType)
                .ThenBy(e => e.SellerType_id)
                .ThenBy(e => e.Seller_Name)
                .ThenBy(e => e.Product_Type)
                .AsNoTracking()
                .ToListAsync();
            return result;
        }
        public async Task<List<fn_GetNotificaitonDetailsReplacements>> fn_GetNotificaitonDetailsReplacementsAsync(string id, string userId)
        {
            var result = await fn_GetNotificaitonDetailsReplacements.FromSqlRaw("SELECT * FROM fn_GetNotificaitonDetailsReplacements({0},{1})", id, userId).AsNoTracking().ToListAsync();
            return result;
        }
        public async Task<fn_GetNotificaitonInfo> fn_GetNotificaitonInfoAsync(string id, string userId)
        {
            var result = await fn_GetNotificaitonInfo
                .FromSqlRaw("SELECT * FROM fn_GetNotificaitonInfo({0},{1})", id, userId)
                .AsNoTracking()
                .ToListAsync();
            return result.FirstOrDefault();
        }
        public async Task<List<fn_GetNotificaitonDetails>> fn_GetNotificaitonDetailsAsync(string id, string userId)
        {
            var result = await fn_GetNotificaitonDetails.FromSqlRaw("SELECT * FROM fn_GetNotificaitonDetails({0},{1})", id, userId).ToListAsync();
            return result;
        }
        public async Task<List<fn_GetReasons>> fn_GetReasonsAsync(string id, string reasonId)
        {
            var result = await fn_GetReasons
                .FromSqlRaw("SELECT * FROM fn_GetReasons({0},{1})", id, reasonId)
                .OrderBy(e => e.Id)
                .ToListAsync();
            return result;
        }




        public async Task<usp_Common> usp_AdminDeleteUserAsync(string userId, string id)
        {
            var result = await usp_Common.FromSqlRaw("EXEC usp_AdminDeleteUser {0},{1}", userId, id).AsNoTracking().ToListAsync();
            return result.FirstOrDefault();
        }           
        public async Task<usp_Common> usp_UpdateNotificationHeaderAsync(string userId, string lcNotification_id, string lcFieldName, string lcFieldvalue)
        {
            var result = await usp_Common
                .FromSqlRaw("EXEC usp_UpdateNotificationHeader {0},{1},{2},{3}", userId, lcNotification_id, lcFieldName, lcFieldvalue)
                .AsNoTracking()
                .ToListAsync();
            return result.FirstOrDefault();
        }        
        public async Task<List<usp_GetDataSets>> usp_GetDataSetsAsync(string id, string parameters)
        {
            var result = await usp_GetDataSets.FromSqlRaw("EXEC usp_GetDataSets {0}, {1}", id, parameters).AsNoTracking().ToListAsync();
            return result;
        }        
        public async Task<usp_Common> usp_CheckNotificationThreshHoldAsync(string changeNotification, string userId)
        {
            var result = await usp_Common.FromSqlRaw("EXEC usp_CheckNotificationThreshHold {0},{1}", changeNotification, userId).AsNoTracking().ToListAsync();
            return result.FirstOrDefault();
        }             
        public async Task<usp_Common> usp_AddReplacementAsync(string id, int notificationId, string userId)
        {
            var result = await usp_Common.FromSqlRaw("EXEC usp_AddReplacement {0},{1},{2}", id, notificationId, userId).AsNoTracking().ToListAsync();
            return result.FirstOrDefault();
        }

        public async Task<X_CurrentUser> usp_LogUserRequestAsync(string openId, string eMail, string path, string query, string agent, string ip, string ident)
        {
            var result = await X_CurrentUser.FromSqlRaw("exec usp_LogUserRequest {0},{1},{2},{3},{4},{5},{6}", openId, eMail, path, query, agent, ip, ident).AsNoTracking().ToListAsync();
            return result.FirstOrDefault();
        }

        public async Task<fn_GetMapExecutionTrendsInfo> fn_GetMapExecutionTrendsInfoAsync(string userId)
        {
            var result = await fn_GetMapExecutionTrendsInfo.FromSqlRaw("SELECT * FROM fn_GetMapExecutionTrendsInfo({0})", userId).AsNoTracking().FirstOrDefaultAsync();
            return result;
        }
        #endregion
    }
}
