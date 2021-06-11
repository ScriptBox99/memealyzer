using System;
using System.Collections.Generic;
using Microsoft.Azure.Functions.Extensions.DependencyInjection;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Azure.Core.Diagnostics;
using Azure.Security.KeyVault.Secrets;
using DotNetEnv;
using Lib;


[assembly: FunctionsStartup(typeof(Memealyzer.Startup))]
namespace Memealyzer
{
    public class Startup : FunctionsStartup
    {
        public override void Configure(IFunctionsHostBuilder builder)
        {
            using var listener = AzureEventSourceListener.CreateConsoleLogger();

            Envs.Load();

            // KeyVault
            var secretClient = new SecretClient(Config.KeyVaultEndpoint, Identity.GetCredentialChain());
            var signalRConnectionString = secretClient.GetSecret(Config.SignalRConnectionStringSecretName);

            // We use the following value to indicate which function to enable/disable.  That way our function isn't listening for messages when it doesn't have to.
            var storageQueueEnabled = Config.MessagingType == "STORAGE_QUEUE";

            var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string> {
                { "StorageConnection:queueServiceUri", Config.StorageQueueEndpoint.ToString() },
                { "AzureWebJobsStorage:accountName", Config.StorageAccountName },
                { "AzureSignalRConnectionString", signalRConnectionString.Value.Value },
                { "ServiceBusConnection:fullyQualifiedNamespace", Config.ServiceBusNamespace },
                { "MessagingType", Config.MessagingType },
                { "ClientSyncQueueName", Config.ClientSyncQueueName },
                { "AzureWebJobs.StorageQueueFunctionRun.Disabled", (!storageQueueEnabled).ToString() },
                { "AzureWebJobs.ServiceBusFunctionRun.Disabled", storageQueueEnabled.ToString() }
            })
            .AddEnvironmentVariables().Build();

            builder.Services.AddSingleton<IConfiguration>(config);
        }
    }
}