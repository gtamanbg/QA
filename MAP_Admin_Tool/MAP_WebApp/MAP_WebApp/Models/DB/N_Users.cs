using System;

namespace MAP_WebApp.Models.DB
{
    public class N_Users
    {
        public string Id { get; set; }
        public string Okta_Id { get; set; }
        public int UserGroup_Id { get; set; }
        public DateTime? LastActive { get; set; }
        public bool Blocked { get; set; }
        public string FirstName { get; set; }
        public string LastName { get; set; }
        public string eMail { get; set; }
        public string CreatedBy { get; set; }
        public DateTime CreatedOn { get; set; }
        public string C_User_Id { get; set; }
        public DateTime C_DateTime { get; set; }
    }
}
