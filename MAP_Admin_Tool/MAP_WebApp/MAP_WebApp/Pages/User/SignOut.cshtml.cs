using MAP_WebApp.Utils;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;

namespace MAP_WebApp.Pages.User
{
    [IgnoreAntiforgeryToken(Order = 1001)]
    public class SignOutModel : PageModel
    {
        private const string loggedOutURL = "/Account/LoggedOut";

        public IActionResult OnPost(string url = "/")
        {
            HttpContext.Session.SetString("r", url.EncodeBase64());

            if (!User.Identity.IsAuthenticated)
                return Redirect(loggedOutURL);
            else
            {
                //HttpContext.SignOutAsync();
                HttpContext.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);

                return new RedirectToPageResult(loggedOutURL);

                //return new SignOutResult(
                //    new[]
                //    {
                //        OktaDefaults.MvcAuthenticationScheme,
                //        CookieAuthenticationDefaults.AuthenticationScheme,
                //    },
                //    new AuthenticationProperties { RedirectUri = loggedOutURL }
                //);
            }
        }
    }
}