using System.Threading.Tasks;
using MAP_WebApp.Utils;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;


namespace MAP_WebApp.Pages
{
    [Authorize]
    public class ProfileModel : BaseModel
    {

        public void OnGet()
        {

        }
    }
}