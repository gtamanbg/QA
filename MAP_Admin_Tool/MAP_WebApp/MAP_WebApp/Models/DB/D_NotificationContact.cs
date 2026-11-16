using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace MAP_WebApp.Models.DB
{
    public class D_NotificationContact
    {
        public int Id { get; set; }
		public int Notification_ID { get; set; }
		public string Location_id { get; set; }
		public string Seller_Name { get; set; }
		public string Category { get; set; }
		public string CategoryEmail { get; set; }
		public string Contact1 { get; set; }
		public string Contact2 { get; set; }
		public string Contact3 { get; set; }
		public string Contact4 { get; set; }
		public string Contact5 { get; set; }
		public string Contact6 { get; set; }
		public string Phone { get; set; }
		public string Address { get; set; }
		public string City { get; set; }
		public int? State_id { get; set; }
		public string Zip { get; set; }
		public string Email1 { get; set; }
		public string Email2 { get; set; }
		public string Email3 { get; set; }
		public string Email4 { get; set; }
		public string Email5 { get; set; }
		public Byte? SourceTable { get; set; }
		public DateTime? C_DateTime { get; set; }
		public string C_User_id { get; set; }
		public bool Changed { get; set; }
		public string Email6 { get; set; }

	}
}
