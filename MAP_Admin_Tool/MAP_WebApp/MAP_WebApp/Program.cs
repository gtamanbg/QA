using Azure.Identity;
using MAP_WebApp.Data;
using MAP_WebApp.Models;
using MAP_WebApp.Utils;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration.AzureAppConfiguration;
using PSSPT_WebApp.Models;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSingleton<IHttpContextAccessor, HttpContextAccessor>();

if (builder.Environment.IsDevelopment())
    builder.Services.AddRazorPages().AddRazorRuntimeCompilation();
else
    builder.Services.AddRazorPages();

var appSettingsEndpoint = Environment.GetEnvironmentVariable(ConfigConstants.AppConfigURL).Decode();
var azureAppConfigLabel = Environment.GetEnvironmentVariable(ConfigConstants.AppConfigLabel).Decode();
var userManagedIdentityId = Environment.GetEnvironmentVariable(ConfigConstants.UserManagedIdentityVar).Decode();
var azureCredential = string.IsNullOrEmpty(userManagedIdentityId) ? new DefaultAzureCredential() : new DefaultAzureCredential(new DefaultAzureCredentialOptions { ManagedIdentityClientId = userManagedIdentityId });

#region Azure App Configurations
if (Uri.TryCreate(appSettingsEndpoint, UriKind.Absolute, out var cfgEndpoint))
{
    builder.Configuration.AddAzureAppConfiguration(options =>
    {
        options
            .Connect(cfgEndpoint, azureCredential)
            .Select(KeyFilter.Any, LabelFilter.Null)
            .ConfigureKeyVault(x => { x.SetCredential(azureCredential); });

        if (!string.IsNullOrEmpty(azureAppConfigLabel))
            options.Select(KeyFilter.Any, azureAppConfigLabel);
    });
}
else
    throw new Exception("MAPQC Startup - no azure app configuration endpoint configured");
builder.Services.AddAzureAppConfiguration();
#endregion

#region CustomSettings: App custom JSON options
var customSettings = builder.Configuration.GetSection(ConfigConstants.AppCusotmSettings).Value.FromJsonToObject<CustomSettings>();
builder.Services.Configure<CustomSettings>(options =>
{
    options.StorageFolder = customSettings.StorageFolder;
    options.TemplateFolder = customSettings.TemplateFolder;
    options.DataContainerURL = customSettings.DataContainerURL;
}
);
#endregion

#region OpenIdFields: OpenId fields setup
var oidf = builder.Configuration.GetSection(ConfigConstants.OidcFields).Value.FromJsonToObject<OpenIdFields>();
builder.Services.Configure<OpenIdFields>(options =>
{
    options.EmailField = oidf.EmailField;
    options.IdField = oidf.IdField;
    options.FullNameField = oidf.FullNameField;
}
);
#endregion

#region OIDC Authentication
var oidcSecrets = builder.Configuration.GetSection(ConfigConstants.Oidc).Value.FromJsonToObject<OIDCSecrets>();
if (oidcSecrets != null && !string.IsNullOrEmpty(oidcSecrets.ClientId) && !string.IsNullOrEmpty(oidcSecrets.ClientSecret))
{
    builder.Services
        .Configure<SecurityStampValidatorOptions>(options =>
            options.ValidationInterval = TimeSpan.FromMinutes(35)
        )
        .AddDistributedMemoryCache()
        .Configure<CookiePolicyOptions>(options =>
        {
            // This lambda determines whether user consent for non-essential cookies is needed for a given request.
            options.CheckConsentNeeded = context => true;
            options.MinimumSameSitePolicy = SameSiteMode.None;
        })
        .Configure<ForwardedHeadersOptions>(options =>
        {
            options.ForwardedHeaders =
                ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto | ForwardedHeaders.XForwardedHost;
        })
        .AddAuthentication(options =>
        {
            options.DefaultAuthenticateScheme = CookieAuthenticationDefaults.AuthenticationScheme;
            options.DefaultSignInScheme = CookieAuthenticationDefaults.AuthenticationScheme;
            options.DefaultSignOutScheme = CookieAuthenticationDefaults.AuthenticationScheme;
            options.DefaultChallengeScheme = OpenIdConnectDefaults.AuthenticationScheme;
            options.DefaultSignOutScheme = OpenIdConnectDefaults.AuthenticationScheme;
        })
        .AddCookie(options =>
        {
            options.AccessDeniedPath = "/s/c/AccessDenied";
            options.LoginPath = "/";
            options.ExpireTimeSpan = TimeSpan.FromMinutes(35);
            options.SlidingExpiration = true;
            options.Cookie.HttpOnly = true;
            options.Cookie.SecurePolicy = CookieSecurePolicy.Always;
        })
        .AddOpenIdConnect(OpenIdConnectDefaults.AuthenticationScheme, options =>
        {
            options.SignInScheme = CookieAuthenticationDefaults.AuthenticationScheme;

            options.Authority = oidcSecrets.Authority;
            options.RequireHttpsMetadata = true;
            options.ClientId = oidcSecrets.ClientId;
            options.ClientSecret = oidcSecrets.ClientSecret;
            options.ResponseType = Microsoft.IdentityModel.Protocols.OpenIdConnect.OpenIdConnectResponseType.Code;
            options.GetClaimsFromUserInfoEndpoint = true;
            options.CallbackPath = oidcSecrets.CallbackPath;
        });
}
else
    throw new Exception("MAPQC Startup - no OIDC ClientId or ClientSecret");

builder.Services
    .AddSession(options =>
    {
        options.Cookie.Name = ".MAPQC.Session";
        options.IdleTimeout = TimeSpan.FromSeconds(10);
        options.Cookie.IsEssential = true;
    });
#endregion

#region DB Models: Register db tables
var dbConnectionString = builder.Configuration.GetSection(ConfigConstants.DBConnectionSectionName).Value;
if (string.IsNullOrEmpty(dbConnectionString))
    throw new Exception("MAPQC Startup - no db connection specified");

builder.Services.AddDbContext<ToolDBContext>(options =>
options.UseSqlServer(
        dbConnectionString,
        sqlServerOptions => sqlServerOptions.CommandTimeout(600)
    )
);
#endregion

builder.Services.AddHsts(options =>
{
    options.MaxAge = TimeSpan.FromDays(7);
    options.IncludeSubDomains = true;
    options.Preload = true;
});

builder.Services.AddMvc(options =>
{
    options.EnableEndpointRouting = false;
});

builder.Services.Configure<OpenIdConnectOptions>(OpenIdConnectDefaults.AuthenticationScheme, options =>
{
    options.Events = new OpenIdConnectEvents
    {

        OnRemoteFailure = context =>
        {
            context.HandleResponse();
            context.Response.Redirect("/Account/AccessDenied");
            return Task.FromResult(0);
        },
    };
});



var app = builder.Build();

app.Use(async (context, next) =>
{
    context.Response.Headers.Append("X-Frame-Options", "DENY");
    context.Response.Headers.Append("Cache-Control", "no-store");

    await next();
});

if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
}
else
{
    app.UseExceptionHandler("/Error");
}

app.UseStatusCodePagesWithReExecute("/Error", "?code={0}");
app.UseHsts();

app.UseHttpsRedirection();
app.UseStaticFiles();

app.UseRouting();
app.UseCookiePolicy();
app.UseSession();
app.UseAuthentication();
app.UseAuthorization();
app.MapRazorPages();

app.Run();
