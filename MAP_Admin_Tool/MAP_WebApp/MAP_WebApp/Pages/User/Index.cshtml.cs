using System.Linq;
using System.Security.Claims;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using MAP_WebApp.Data;
using MAP_WebApp.Utils;

namespace MAP_WebApp.Pages.User
{
    [Authorize]
    public class IndexModel : BaseModel
    {
        public IndexModel(ToolDBContext context, IHttpContextAccessor accessor)
        {
            _context = context;
            _accessor = accessor;
        }

        public ClaimsIdentity Userx;
        public string UserName = "";
        public string GivenName = "";
        public string FamilyName = "";

        public IActionResult OnGet()
        {
            if (!initPage())
                return new ForbidResult();

            Userx = HttpContext.User.Identity as ClaimsIdentity;
            foreach(var claim in Userx.Claims)
            {
                if (claim.Type == "preferred_username")
                    UserName = claim.Value;
                else if (claim.Type == "given_name")
                    GivenName = claim.Value;
                else if (claim.Type == "family_name")
                    FamilyName = claim.Value;
            }

            return Page();
        }
    }
}