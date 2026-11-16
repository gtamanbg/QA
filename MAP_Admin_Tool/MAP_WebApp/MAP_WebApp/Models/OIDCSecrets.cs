#nullable disable warnings
namespace PSSPT_WebApp.Models
{
    public class OIDCSecrets
    {
        public string Authority { get; set; }
        public string ClientId { get; set; }
        public string ClientSecret { get; set; }
        public string CallbackPath { get; set; }
    }
}
