using System;
using System.Reflection;

namespace ChannelForge.Private.Transport
{
    public static class ChannelForgePinnedHttpTransport
    {
        public const string ContractName = "ChannelForgePinnedHttpTransport";
        public const int ContractVersion = 1;

        public static bool HasRequiredCapabilities()
        {
            if (Environment.Version.Major < 10)
            {
                return false;
            }

            var handlerType = Type.GetType(
                "System.Net.Http.SocketsHttpHandler, System.Net.Http",
                throwOnError: false,
                ignoreCase: false);

            if (handlerType == null)
            {
                return false;
            }

            return handlerType.GetProperty(
                       "ConnectCallback",
                       BindingFlags.Instance | BindingFlags.Public) != null;
        }
    }
}
