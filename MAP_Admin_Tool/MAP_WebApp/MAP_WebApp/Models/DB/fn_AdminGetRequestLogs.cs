namespace MAP_WebApp.Models.DB
{
    public class fn_AdminGetRequestLogs
    {
        public int Id { get; set; }
        public string UserName { get; set; }
        public string OktaUser_Id { get; set; }
        public string Path { get; set; }
        public string UserAgent { get; set; }
        public string IpAddress { get; set; }
        public string TraceIdent { get; set; }
        public string LoggedOn { get; set; }

    }
}
