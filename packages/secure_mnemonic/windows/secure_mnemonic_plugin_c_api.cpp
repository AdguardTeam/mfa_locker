#include "include/secure_mnemonic/secure_mnemonic_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "secure_mnemonic_plugin.h"

void SecureMnemonicPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) 
{
  secure_mnemonic::SecureMnemonicPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
