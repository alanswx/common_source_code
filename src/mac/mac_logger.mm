#import <Cocoa/Cocoa.h>
#include "mac_logger.h"
#include <mutex>
#include <sstream>
#include <chrono>
#include <iomanip>
#include <vector>
#include <string>
#include <algorithm>

static std::mutex g_log_mutex;
static std::string g_log_buffer;
static std::vector<std::string> g_missing_roms;
static std::vector<std::string> g_found_roms;
static std::vector<std::pair<std::string, std::string>> g_loaded_rom_paths;
static std::string g_app_name = "retropc";

static std::string get_timestamp()
{
	auto now = std::chrono::system_clock::now();
	auto in_time_t = std::chrono::system_clock::to_time_t(now);
	auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()) % 1000;
	std::stringstream ss;
	ss << std::put_time(std::localtime(&in_time_t), "%H:%M:%S") << '.' << std::setfill('0') << std::setw(3) << ms.count();
	return ss.str();
}

void mac_log(const char *format, ...)
{
	char buffer[2048];
	va_list args;
	va_start(args, format);
	vsnprintf(buffer, sizeof(buffer), format, args);
	va_end(args);

	std::string ts = get_timestamp();
	std::lock_guard<std::mutex> lock(g_log_mutex);
	g_log_buffer += "[" + ts + "] " + buffer;
	if(g_log_buffer.back() != '\n') {
		g_log_buffer += "\n";
	}
	fprintf(stderr, "[%s] %s%s", ts.c_str(), buffer, (buffer[strlen(buffer)-1] == '\n') ? "" : "\n");
}

void mac_record_missing_rom(const char *filename, const char *app_name)
{
	std::lock_guard<std::mutex> lock(g_log_mutex);
	if(app_name && app_name[0] != '\0') {
		g_app_name = app_name;
	}
	if(filename) {
		for(const auto &r : g_missing_roms) {
			if(strcasecmp(r.c_str(), filename) == 0) return;
		}
		g_missing_roms.push_back(filename);
	}
}

void mac_record_found_rom(const char *filename, const char *resolved_path)
{
	if(filename) {
		std::lock_guard<std::mutex> lock(g_log_mutex);
		bool exists = false;
		for(const auto &f : g_found_roms) {
			if(strcasecmp(f.c_str(), filename) == 0) {
				exists = true;
				break;
			}
		}
		if(!exists) {
			g_found_roms.push_back(filename);
			g_loaded_rom_paths.push_back({filename, resolved_path ? resolved_path : ""});
		}
	}
	mac_log("[ROM OK] Loaded '%s' from: %s", filename ? filename : "unknown", resolved_path ? resolved_path : "unknown");
}

struct RomRequirement {
	std::string displayName;
	std::vector<std::string> alternates;
};

static std::vector<RomRequirement> get_requirements_for_machine(const std::string &mach)
{
	std::string m = mach;
	std::transform(m.begin(), m.end(), m.begin(), ::tolower);

	// Consoles / Cartridge-based systems: NO required system ROMs
	if(m == "pcengine" || m == "mastersystem" || m == "gamegear" ||
	   m == "sc3000" || m == "pv1000" || m == "tvboy" || m == "familybasic" ||
	   m == "z80tvgame_i8255" || m == "z80tvgame_z80pio") {
		return {};
	}

	if(m == "colecovision") {
		return {{"COLECO.ROM", {"COLECO.ROM"}}};
	}
	if(m == "scv") {
		return {{"BIOS.ROM", {"BIOS.ROM"}}};
	}
	if(m == "pyuta") {
		return {{"IPL.ROM or BASIC.ROM", {"IPL.ROM", "BASIC.ROM"}}};
	}
	if(m == "rx78") {
		return {{"IPL.ROM", {"IPL.ROM"}}};
	}
	if(m == "jr100") {
		return {{"BASIC.ROM", {"BASIC.ROM", "JR100.ROM"}}};
	}
	if(m == "jr800") {
		return {{"BASIC.ROM", {"BASIC.ROM"}}};
	}
	if(m == "m5") {
		return {{"IPL.ROM", {"IPL.ROM"}}};
	}
	if(m == "pv2000") {
		return {{"IPL.ROM", {"IPL.ROM"}}};
	}
	if(m == "phc20" || m == "phc25") {
		return {
			{"BASIC.ROM", {"BASIC.ROM"}},
			{"FONT.ROM", {"FONT.ROM"}}
		};
	}
	if(m == "multi8") {
		return {
			{"BASIC.ROM", {"BASIC.ROM"}},
			{"FONT.ROM", {"FONT.ROM"}}
		};
	}
	if(m == "bmjr") {
		return {
			{"BASIC.ROM", {"BASIC.ROM", "BAS.ROM"}},
			{"FONT.ROM", {"FONT.ROM"}},
			{"MONITOR.ROM", {"MONITOR.ROM", "MON.ROM"}}
		};
	}
	if(m == "pasopia") {
		return {
			{"TBASIC.ROM", {"TBASIC.ROM", "TBASIC10.ROM", "TBASIC11.ROM", "OABASIC.ROM", "PASCAL.ROM"}},
			{"FONT.ROM", {"FONT.ROM"}}
		};
	}
	if(m == "pasopia7" || m == "pasopia7lcd") {
		return {
			{"BIOS.ROM", {"BIOS.ROM"}},
			{"BASIC.ROM", {"BASIC.ROM"}},
			{"FONT.ROM", {"FONT.ROM"}}
		};
	}
	if(m == "smc70" || m == "smc777") {
		return {
			{"SMCROM.DAT", {"SMCROM.DAT", "SMC70ROM.DAT", "SMC70ROMA.DAT", "SMC70ROMB.DAT", "SMC777ROM.DAT", "BASICROM.DAT"}}
		};
	}
	if(m == "pc6001") {
		return {
			{"BASICROM.60", {"BASICROM.60"}},
			{"CGROM60.60", {"CGROM60.60"}}
		};
	}
	if(m == "pc8001" || m == "pc8001mk2" || m == "pc8001mk2sr") {
		return {
			{"N80.ROM", {"N80.ROM", "N80_1.ROM", "PC88.ROM"}}
		};
	}
	if(m == "pc8201" || m == "pc8201a") {
		return {{"IPL.ROM", {"IPL.ROM"}}};
	}
	if(m == "pc100") {
		return {{"IPL.ROM or KANJI.ROM", {"IPL.ROM", "KANJI.ROM"}}};
	}
	if(m == "pc2001") {
		return {{"0000-0FFF.ROM", {"0000-0FFF.ROM", "BASIC.ROM"}}};
	}
	if(m.rfind("pc8801", 0) == 0) {
		return {
			{"N88.ROM", {"N88.ROM", "N88_0.ROM", "PC88.ROM"}},
			{"N80.ROM", {"N80.ROM", "N80_1.ROM", "PC88.ROM"}}
		};
	}
	if(m.rfind("pc98", 0) == 0) {
		if(m == "pc98ha" || m == "pc98lt") {
			return {
				{"IPL.ROM", {"IPL.ROM", "BIOS.ROM"}},
				{"ROMDRV.ROM", {"ROMDRV.ROM"}}
			};
		}
		return {
			{"FONT.ROM", {"FONT.ROM", "FONT16.ROM", "FONT24.ROM"}}
		};
	}
	if(m.rfind("fmr", 0) == 0) {
		return {{"IPL.ROM", {"IPL.ROM"}}};
	}
	if(m.rfind("fm16beta", 0) == 0) {
		return {{"SUBSYS.ROM", {"SUBSYS.ROM", "SUB.ROM"}}};
	}
	if(m == "fm16pi") {
		return {{"CART.ROM or KANJI.ROM", {"CART.ROM", "KANJI.ROM"}}};
	}
	if(m.rfind("fm", 0) == 0) {
		return {
			{"FBASIC30.ROM", {"FBASIC30.ROM", "FBASIC300.ROM", "FBASIC301.ROM", "FBASIC302.ROM"}},
			{"SUBSYS_C.ROM", {"SUBSYS_C.ROM", "SUBSYS_A.ROM", "SUBSYSCG.ROM"}}
		};
	}
	if(m == "msx1" || m == "px7") {
		return {
			{"MSX.ROM", {"MSX.ROM", "MSXJ.ROM", "BASIC.ROM"}}
		};
	}
	if(m == "msx2" || m == "fsa1") {
		return {
			{"MSX2.ROM", {"MSX2.ROM", "MSX2J.ROM"}},
			{"MSX2EXT.ROM", {"MSX2EXT.ROM", "MSX2JEXT.ROM"}}
		};
	}
	if(m == "msx2p") {
		return {
			{"MSX2P.ROM", {"MSX2P.ROM"}},
			{"MSX2PEXT.ROM", {"MSX2PEXT.ROM", "MSX2EXT.ROM"}}
		};
	}
	if(m.rfind("mz", 0) == 0) {
		return {
			{"IPL.ROM", {"IPL.ROM", "MZ-1E05.ROM", "MZ-1E14.ROM", "MZ-1E18.ROM", "MZ-1E30.ROM", "MZ-80FIO.ROM"}},
			{"FONT.ROM", {"FONT.ROM", "FONT80.ROM", "ANK16.ROM", "FNT0816.X1"}}
		};
	}
	if(m.rfind("x1", 0) == 0) {
		return {
			{"IPL.ROM", {"IPL.ROM", "CZ8RB.ROM"}},
			{"FONT.ROM", {"FONT.ROM", "FNT0816.X1", "ANK16.ROM"}}
		};
	}
	if(m == "fp1100") {
		return {
			{"BASIC.ROM", {"BASIC.ROM"}},
			{"SUB1.ROM", {"SUB1.ROM"}}
		};
	}
	if(m == "fp200") {
		return {{"BIOS.ROM", {"BIOS.ROM"}}};
	}
	if(m == "fx9000p") {
		return {{"BASIC.ROM", {"BASIC.ROM"}}};
	}
	if(m == "hc20" || m == "hx20") {
		return {{"BASIC.ROM", {"BASIC.ROM"}}};
	}
	if(m == "hc40") {
		return {{"EXT.ROM", {"EXT.ROM"}}};
	}
	if(m == "hc80") {
		return {
			{"SYS.ROM", {"SYS.ROM"}},
			{"BASIC.ROM", {"BASIC.ROM"}}
		};
	}
	if(m.rfind("qc10", 0) == 0) {
		return {
			{"IPL.ROM", {"IPL.ROM"}},
			{"FONT.ROM", {"FONT.ROM"}}
		};
	}
	if(m.rfind("j3100", 0) == 0) {
		return {
			{"IPL.ROM", {"IPL.ROM"}},
			{"FONT.ROM", {"FONT.ROM"}}
		};
	}
	if(m == "jx") {
		return {
			{"IPL.ROM", {"IPL.ROM"}},
			{"FONT.ROM", {"FONT.ROM"}}
		};
	}
	if(m == "n5200") {
		return {{"IPL.ROM", {"IPL.ROM"}}};
	}
	if(m == "svi3x8") {
		return {{"SVI318.ROM or SVI328.ROM", {"SVI318.ROM", "SVI328.ROM", "SVI328a.ROM"}}};
	}
	if(m == "tk80bs") {
		return {{"TK80.ROM", {"TK80.ROM"}}};
	}
	if(m == "tk85" || m == "mp85") {
		return {{"TK85.ROM", {"TK85.ROM"}}};
	}
	if(m == "ex80bs" || m == "babbage2nd" || m == "trnjr" || m == "ys6464a" || m == "crc80" || m == "smb80te") {
		return {{"MON.ROM", {"MON.ROM"}}};
	}
	if(m == "mycomz80a") {
		return {{"BIOS.ROM or BASIC.ROM", {"BIOS.ROM", "BASIC.ROM"}}};
	}
	if(m == "yalky" || m == "yis" || m == "cefucom21" || m == "m23" || m == "m68") {
		return {{"FONT.ROM", {"FONT.ROM"}}};
	}
	if(m == "x07") {
		return {
			{"BASIC.ROM", {"BASIC.ROM"}},
			{"FONT.ROM", {"FONT.ROM"}}
		};
	}
	if(m == "t250" || m == "map1010") {
		return {{"BOOT.ROM", {"BOOT.ROM"}}};
	}
	if(m == "bx1") {
		return {{"X-7101B.ROM", {"X-7101B.ROM"}}};
	}
	if(m == "micom_mahjong") {
		return {
			{"PRG.ROM", {"PRG.ROM"}},
			{"CG.ROM", {"CG.ROM"}}
		};
	}
	if(m == "bubcom80") {
		return {{"BASIC.ROM", {"BASIC.ROM"}}};
	}

	return {};
}

static bool is_found_locked(const std::string &name)
{
	for(const auto &f : g_found_roms) {
		if(strcasecmp(f.c_str(), name.c_str()) == 0) return true;
	}
	return false;
}

static std::vector<std::string> get_required_missing_roms_locked()
{
	std::vector<std::string> missing;
	auto reqs = get_requirements_for_machine(g_app_name);
	for(const auto &req : reqs) {
		bool satisfied = false;
		for(const auto &alt : req.alternates) {
			if(is_found_locked(alt)) {
				satisfied = true;
				break;
			}
		}
		if(!satisfied) {
			missing.push_back(req.displayName);
		}
	}
	return missing;
}

static std::vector<std::string> get_optional_missing_roms_locked()
{
	std::vector<std::string> optional_missing;
	auto reqs = get_requirements_for_machine(g_app_name);

	for(const auto &r : g_missing_roms) {
		// Ignore runtime state files (.BIN, .NVRAM, etc.)
		std::string upper = r;
		std::transform(upper.begin(), upper.end(), upper.begin(), ::toupper);
		if(upper.size() >= 4 && upper.compare(upper.size() - 4, 4, ".BIN") == 0) {
			continue;
		}

		// Check if it's already an alternate of a required ROM
		bool is_required_alt = false;
		for(const auto &req : reqs) {
			for(const auto &alt : req.alternates) {
				if(strcasecmp(alt.c_str(), r.c_str()) == 0) {
					is_required_alt = true;
					break;
				}
			}
			if(is_required_alt) break;
		}
		if(!is_required_alt) {
			optional_missing.push_back(r);
		}
	}
	return optional_missing;
}

bool mac_has_missing_roms()
{
	std::lock_guard<std::mutex> lock(g_log_mutex);
	return !get_required_missing_roms_locked().empty();
}

std::vector<std::string> mac_get_missing_roms()
{
	std::lock_guard<std::mutex> lock(g_log_mutex);
	return get_required_missing_roms_locked();
}

std::string mac_get_log_text()
{
	std::lock_guard<std::mutex> lock(g_log_mutex);
	std::stringstream ss;
	ss << "======================================================================\n";
	ss << " RetroPC Diagnostic Log & ROM Status: " << g_app_name << "\n";
	ss << " ROM Folder: ~/Library/Application Support/CommonSourceCodeProject/" << g_app_name << "/\n";
	ss << "======================================================================\n\n";

	auto reqs = get_requirements_for_machine(g_app_name);
	if(!reqs.empty()) {
		ss << "--- REQUIRED SYSTEM ROMS ---\n";
		for(const auto &req : reqs) {
			std::string matchedAlt = "";
			for(const auto &alt : req.alternates) {
				if(is_found_locked(alt)) {
					matchedAlt = alt;
					break;
				}
			}
			if(!matchedAlt.empty()) {
				ss << "  [OK] " << req.displayName << " (Loaded as: " << matchedAlt << ")\n";
			} else {
				ss << "  [MISSING!] " << req.displayName << " -> Required for boot\n";
			}
		}
		ss << "\n";
	} else {
		ss << "--- SYSTEM STATUS ---\n";
		ss << "  This machine does not require internal system ROMs (cartridge-based).\n\n";
	}

	auto opt_missing = get_optional_missing_roms_locked();
	if(!opt_missing.empty()) {
		ss << "--- OPTIONAL / EXPANSION PROBES (Not required for boot) ---\n";
		for(const auto &opt : opt_missing) {
			ss << "  [OPTIONAL NOT FOUND] " << opt << "\n";
		}
		ss << "\n";
	}

	if(!g_loaded_rom_paths.empty()) {
		ss << "--- LOADED ROM FILES ---\n";
		for(const auto &p : g_loaded_rom_paths) {
			ss << "  • " << p.first << " => " << p.second << "\n";
		}
		ss << "\n";
	}

	ss << "--- EMULATION EXECUTION LOG ---\n";
	ss << g_log_buffer;

	return ss.str();
}

std::string mac_get_app_rom_directory()
{
	std::lock_guard<std::mutex> lock(g_log_mutex);
	NSString *home = NSHomeDirectory();
	NSString *dir = [NSString stringWithFormat:@"%@/Library/Application Support/CommonSourceCodeProject/%s", home, g_app_name.c_str()];
	return [dir UTF8String];
}

void mac_open_rom_directory_in_finder()
{
	std::string dir = mac_get_app_rom_directory();
	NSString *path = [NSString stringWithUTF8String:dir.c_str()];
	[[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
	[[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
}

