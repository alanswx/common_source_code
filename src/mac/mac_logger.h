#ifndef _MAC_LOGGER_H_
#define _MAC_LOGGER_H_

#include <string>
#include <vector>

void mac_log(const char *format, ...);
void mac_record_missing_rom(const char *filename, const char *app_name);
void mac_record_found_rom(const char *filename, const char *resolved_path);
bool mac_has_missing_roms();
std::vector<std::string> mac_get_missing_roms();
std::string mac_get_log_text();
std::string mac_get_app_rom_directory();
void mac_open_rom_directory_in_finder();

#endif
