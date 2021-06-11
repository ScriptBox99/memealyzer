using System;
using System.Net.Http;
using System.Net.Http.Json;
using System.Threading.Tasks;
using Azure.AI.FormRecognizer;
using Azure.AI.TextAnalytics;
using Azure.Data.AppConfiguration;
using Azure.Identity;
using Azure.Security.KeyVault.Secrets;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Lib.Data;
using Lib.Messaging;
using Lib.Model;
using Lib.Storage;

namespace Lib
{
    public class Clients : IAsyncDisposable
    {
        public SecretClient SecretClient;
        public ChainedTokenCredential credential = Identity.GetCredentialChain();
        public StorageClient StorageClient;
        public IMessagingProvider MessagingProvider;
        public TextAnalyticsClient TextAnalyticsClient;
        public FormRecognizerClient FormRecognizerClient;
        public ConfigurationClient ConfigurationClient;
        public IDataProvider DataProvider;
        private HttpClient httpClient = new HttpClient();

        public Clients()
        {
        }

        public async Task InitializeAsync()
        {
            // Data Provider            
            DataProvider = DataProviderFactory.Get(Config.StorageType);
            await DataProvider.InitializeAsync(credential);

            // Messaging Provider            
            MessagingProvider = MessagingProviderFactory.Get(Config.MessagingType);
            await MessagingProvider.InitializeAsync(credential, DataProvider);

            // App Config
            ConfigurationClient = new ConfigurationClient(Config.AppConfigEndpoint, credential);

            // Storage
            StorageClient = new StorageClient();
            await StorageClient.InitializeAsync(credential);

            // FormRecognizerClient
            FormRecognizerClient = new FormRecognizerClient(Config.FormRecognizerEndpoint, credential);

            // TextAnalyticsClient
            TextAnalyticsClient = new TextAnalyticsClient(Config.TextAnalyticsEndpoint, credential);
        }

        public ValueTask DisposeAsync()
        {
            if (DataProvider != null)
            {
                DataProvider.Dispose();
            }
            
            if (MessagingProvider != null)
            {
                return MessagingProvider.DisposeAsync();
            }
            else
            {
                return new ValueTask();
            }
        }

        public async Task<Image> EnqueueImageAsync(Image image = null)
        {
            if (image?.Url is null || string.IsNullOrEmpty(image.Url))
            {
                var memeImage = await httpClient.GetFromJsonAsync<Image>(Config.MemeEndpoint);
                image.Url = memeImage.Url;
            }

            // Get Image Stream
            using var imageStream = await httpClient.GetStreamAsync(image.Url);

            // Upload to Blob
            var blobInfo = await StorageClient.UploadBlob(image.BlobName, imageStream);

            Console.WriteLine($"Uploaded to Blob Storage: {blobInfo.Uri}");

            image.BlobUri = blobInfo.Uri.ToString();

            // Send Queue Message
            var sendReceipt = await MessagingProvider.ImageQueueClient.SendMessageAsync(new ImageQueueMessage { Image = image });

            //Console.WriteLine($"Added to Queue: {sendReceipt.Message.Id}");
            return image;
        }
    }
}
