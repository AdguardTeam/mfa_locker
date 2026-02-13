#include "include/biometric_cipher/biometric_cipher_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "biometric_cipher_plugin.h"

void BiometricCipherPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) 
{
  biometric_cipher::BiometricCipherPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
