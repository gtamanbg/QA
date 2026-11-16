using Azure.Identity;
using Azure.Storage.Blobs;
using MAP_WebApp.Models;
using Microsoft.AspNetCore.Mvc.Rendering;
using Newtonsoft.Json;
using PM_WebApp.Models.DB;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace MAP_WebApp.Utils
{
    public class AzureAction
    {
        public static bool UploadToAzure(CustomSettings customSettings, string azureId, Stream file, bool overwrite = false)
        {
            var containerUrl = customSettings.DataContainerURL;
            var userManagedIdentityId = Environment.GetEnvironmentVariable(ConfigConstants.UserManagedIdentityVar).Decode();
            var azureCredential = string.IsNullOrEmpty(userManagedIdentityId) ? new DefaultAzureCredential() : new DefaultAzureCredential(new DefaultAzureCredentialOptions { ManagedIdentityClientId = userManagedIdentityId });
            BlobServiceClient blobServiceClient = new BlobServiceClient(new Uri(containerUrl), azureCredential);
            string filesFolder = customSettings.StorageFolder;

            var fullFilePath = filesFolder.AppendURL(azureId);
            BlobContainerClient blobContainer = blobServiceClient.GetBlobContainerClient("");
            BlobClient blobClient = blobContainer.GetBlobClient(fullFilePath);
            file.Position = 0;
            var result = blobClient.Upload(file, overwrite);
            var status = result.GetRawResponse().Status;
            if (status >= 200 && status <= 299)
                return true;
            else
                throw new Exception("Error Upload File In Azure!");
        }

        public static MemoryStream DownloadFromAzure(CustomSettings customSettings, string azureId, bool template = false)
        {
            var containerUrl = customSettings.DataContainerURL;
            var userManagedIdentityId = Environment.GetEnvironmentVariable(ConfigConstants.UserManagedIdentityVar).Decode();
            var azureCredential = string.IsNullOrEmpty(userManagedIdentityId) ? new DefaultAzureCredential() : new DefaultAzureCredential(new DefaultAzureCredentialOptions { ManagedIdentityClientId = userManagedIdentityId });
            BlobServiceClient blobServiceClient = new BlobServiceClient(new Uri(containerUrl), azureCredential);
            string filesFolder = template ? customSettings.TemplateFolder : customSettings.StorageFolder;

            var fullFilePath = filesFolder.AppendURL(azureId);
            BlobContainerClient blobContainer = blobServiceClient.GetBlobContainerClient("");
            BlobClient blobClient = blobContainer.GetBlobClient(fullFilePath);
            MemoryStream downloadStream = new MemoryStream();
            var result = blobClient.DownloadTo(downloadStream);
            var status = result.Status;
            if (status >= 200 && status <= 299)
            {
                downloadStream.Position = 0;
                return downloadStream;
            }
            else
                throw new Exception("Error Download File From Azure!");
        }

        public static bool DeleteFromAzure(CustomSettings customSettings, string azureId)
        {
            var containerUrl = customSettings.DataContainerURL;
            var userManagedIdentityId = Environment.GetEnvironmentVariable(ConfigConstants.UserManagedIdentityVar).Decode();
            var azureCredential = string.IsNullOrEmpty(userManagedIdentityId) ? new DefaultAzureCredential() : new DefaultAzureCredential(new DefaultAzureCredentialOptions { ManagedIdentityClientId = userManagedIdentityId });
            BlobServiceClient blobServiceClient = new BlobServiceClient(new Uri(containerUrl), azureCredential);
            string filesFolder = customSettings.StorageFolder;

            var fullFilePath = filesFolder.AppendURL(azureId);
            BlobContainerClient blobContainer = blobServiceClient.GetBlobContainerClient("");
            BlobClient blobClient = blobContainer.GetBlobClient(fullFilePath);
            var result = blobClient.DeleteIfExists();
            var response = result.GetRawResponse();
            if (result.Value == false || response.Status >= 200 && response.Status <= 299)
                return true;
            else
                throw new Exception("Error Delete File In Azure!");
        }
    }
    public class Const
    {
        public const string ErrorMessage = "Please contact administrator.";
        public const string Error404 = "Resource not found. Please contact your administrator for more information.";
        public const string Error403 = "Access Denied. You dont have permitions to open that page. Please contact your administrator for more information.";
        public const string ErrorXXX = "An error occurred while processing your request. Please contact your administrator for more information.";
        public const string Key = "Qx#NQhvG$nwPyg@S287Fiz2!d0npM#cU";
    }

    public static class ConfigConstants
    {
        public const string AppConfigURL = "_AppConfigURL";
        public const string UserManagedIdentityVar = "_umiId";
        public const string AppConfigLabel = "_AppConfigLabel";
        public const string AppCusotmSettings = "_customSettings";
        public const string Oidc = "_oidcSecret";
        public const string OidcFields = "_oidcFields";
        public const string DBConnectionSectionName = "_dbConnectionString";
        public const string DBConnectionString = "_dbConnectionStringLocal";
    }

    public class Encode_Decode
    {
        public class AES
        {
            private byte[] key;
            public AES(string SecretKey)
            {
                string k = Pass2Key(SecretKey);
                key = Encoding.UTF8.GetBytes(k);
            }
#nullable enable
            public string? Encrypt(string plainText)
            {
                if (plainText == null || plainText.Length <= 0)
                {
                    return null;
                }

                if (key == null || key.Length <= 0)
                {
                    throw new ArgumentNullException("key");
                }

                byte[] encrypted;
                using (var aes = Aes.Create())
                {
                    aes.BlockSize = 128;
                    aes.Key = key;
                    aes.Mode = CipherMode.CBC;
                    aes.Padding = PaddingMode.Zeros;
                    aes.IV = key;
                    ICryptoTransform encryptor = aes.CreateEncryptor(aes.Key, aes.IV);
                    using (var msEncrypt = new MemoryStream())
                    {
                        using (var csEncrypt = new CryptoStream(msEncrypt, encryptor, CryptoStreamMode.Write))
                        {
                            using (var swEncrypt = new StreamWriter(csEncrypt))
                            {
                                swEncrypt.Write(plainText);
                            }

                            encrypted = msEncrypt.ToArray();
                        }
                    }
                }

                return System.Convert.ToBase64String(encrypted);
            }
#nullable disable
            public string Decrypt(string encrypted)
            {
                try
                {

                    byte[] cipherText = System.Convert.FromBase64String(encrypted);
                    if (cipherText == null || cipherText.Length <= 0)
                    {
                        throw new ArgumentNullException("cipherText");
                    }

                    if (key == null || key.Length <= 0)
                    {
                        throw new ArgumentNullException("key");
                    }

                    string plaintext;
                    using (var aes = Aes.Create())
                    {
                        aes.BlockSize = 128;
                        aes.Key = key;
                        aes.Mode = CipherMode.CBC;
                        aes.Padding = PaddingMode.Zeros;
                        aes.IV = key;
                        ICryptoTransform decryptor = aes.CreateDecryptor(aes.Key, aes.IV);
                        using (var msDecrypt = new MemoryStream(cipherText))
                        {
                            using (var csDecrypt = new CryptoStream(msDecrypt, decryptor, CryptoStreamMode.Read))
                            {
                                using (var srDecrypt = new StreamReader(csDecrypt))
                                {
                                    plaintext = srDecrypt.ReadToEnd();
                                }
                            }
                        }
                    }

                    return plaintext;
                }
                catch
                {
                    return encrypted;
                }
            }

            public string Pass2Key(string SecretKey)
            {
                SHA512 sHA512 = SHA512.Create();
                return System.Convert.ToBase64String(sHA512.ComputeHash(Encoding.UTF8.GetBytes(SecretKey))).Substring(0, 16);
            }
        }
    }

    public static class Extensions
    {
        public static string NullIfWhiteSpace(this string value)
        {
            if (String.IsNullOrWhiteSpace(value)) { return null; }
            return value;
        }
        public static bool IsNumeric(this string str, NumberStyles style = NumberStyles.Number,
        CultureInfo culture = null)
        {
            double num;
            if (culture == null) culture = CultureInfo.InvariantCulture;
            return Double.TryParse(str, style, culture, out num) && !String.IsNullOrWhiteSpace(str);
        }

        public static string st(this string s)
        {
            if (s == null)
                return null;
            return s.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;").Replace("'", "&#x27;").Replace("/", "&#x2F;");
        }
        public static string ToStringDef(this object s, string def)
        {
            if (s == null)
                return def;
            return s.ToString() ;
        }

        public static List<SelectListItem> ToDropdownList(this IEnumerable<DBDropDownListResult> records, object selectedValue = null)
        {
            return records.Select(a => new SelectListItem
            {
                Value = a.Id.ToString(),
                Text = a.Value,
                Selected = (selectedValue != null ? a.Value == selectedValue.ToString() : a.Selected)
            }).ToList();

        }
        public static string EncodeBase64(this string s)
        {
            if (s == null)
            {
                return null;
            }

            byte[] textAsBytes = System.Text.Encoding.UTF8.GetBytes(s);
            return System.Convert.ToBase64String(textAsBytes);
        }

        public static string DecodeBase64(this string encodedText)
        {
            if (encodedText == null)
            {
                return null;
            }

            byte[] textAsBytes = System.Convert.FromBase64String(encodedText);
            return System.Text.Encoding.UTF8.GetString(textAsBytes);
        }
        public static string Decode(this string value)
        {
            if (string.IsNullOrEmpty(value))
                return "";
            else
            {
                Encode_Decode.AES aes = new Encode_Decode.AES(Const.Key);
                return aes.Decrypt(value).Replace("\0", "");
            }
        }
        public static string Encode(this string value)
        {
            Encode_Decode.AES aes = new Encode_Decode.AES(Const.Key);
            return aes.Encrypt(value);
        }
#nullable enable
        public static T? FromJsonToObject<T>(this string? str)
        {
            if (string.IsNullOrEmpty(str))
                return default(T);
            else
                return JsonConvert.DeserializeObject<T>(str);
        }
#nullable disable
        public static string AppendURL(this string uri1, string uri2)
        {
            uri1 = uri1.TrimEnd('/');
            uri2 = uri2.TrimStart('/');
            return string.Format("{0}/{1}", uri1, uri2);
        }
        public static int? ToNullableInt(this string s, int? defVal = null)
        {
            try
            {
                if (s == null)
                    return defVal;
                return int.Parse(s);
            }
            catch
            {
                return defVal;
            }
        }
        public static int ToInt(this string s, int defVal)
        {
            try
            {
                if (s == null)
                    return defVal;
                return int.Parse(s);
            }
            catch
            {
                return defVal;
            }
        }
    }
}
