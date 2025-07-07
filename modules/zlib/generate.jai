#scope_file

AT_COMPILE_TIME :: true;

SOURCE_PATH :: "src/zlib-1.3.1";

#scope_export

generate_zlib :: (args: [] string) -> bool {
    compile       := array_find(args, "-compile");
    compile_debug := array_find(args, "-debug");
    compile_clean := array_find(args, "-clean");

    os_target := OS;

    // Set this to false to only build for your architecture.
    macos_universal_binaries := true;

    if compile {
        if !check_dependencies(os_target) {
            return false;
        }

        if !is_directory(SOURCE_PATH) {
            log_error("Source directory \"%\" does not exist. zlib releases can be obtained from https://zlib.net", SOURCE_PATH);
            return false;
        }

        if os_target == {
            case .MACOS;
                success  := zlib_compile(os_target, CPU, build_shared_libraries = true,  debug = compile_debug, clean = compile_clean, macos_universal_binaries);
                success &&= zlib_compile(os_target, CPU, build_shared_libraries = false, debug = compile_debug, clean = compile_clean, macos_universal_binaries);
                if !success return false;

            case;
                success  := zlib_compile(os_target, build_shared_libraries = true,  debug = compile_debug, clean = compile_clean);
                success &&= zlib_compile(os_target, build_shared_libraries = false, debug = compile_debug, clean = compile_clean);
                if !success return false;
        }
    }

    print("Generating bindings...\n");

    output_filename: string;
    opts: Generate_Bindings_Options;
    {
        using opts;

        os = os_target;

        if os_target == {
            case .WINDOWS;
                array_add(*libpaths, "windows");
                array_add(*libnames, "zlib");
                array_add(*extra_clang_arguments, "-DWIN32_LEAN_AND_MEAN");
                array_add(*include_paths, "windows_static_build");

                output_filename = "windows.jai";

            case .LINUX;
                array_add(*libpaths, "linux");
                array_add(*libnames, "libz");
                array_add(*include_paths, "linux_static_build");

                output_filename = "linux.jai";

            case .MACOS;
                array_add(*libpaths, "macos");
                array_add(*libnames, "libz");
                array_add(*include_paths, "macos_static_build");

                output_filename = "macos.jai";
                cpu = CPU;

            case;
                assert(false, "@Incomplete: os_target == % is currently not supported.", os_target);
        }

        array_add(*source_files, tprint("%/zlib.h", SOURCE_PATH));
    }

    return generate_bindings(opts, output_filename);
}

#scope_file

get_platform_name :: (os_target: Operating_System_Tag) -> string {
    if os_target == {
        case .WINDOWS;  return "windows";
        case .LINUX;    return "linux";
        case .MACOS;    return "macos";
    }

    assert(false, "@Incomplete: os_target == % is currently not supported.", os_target);

    return "";
}

zlib_compile :: (os_target: Operating_System_Tag, cpu_target := CPU, build_shared_libraries := true, debug := false, clean := false, macos_universal_binaries := true) -> bool {
    shared_or_static := ifx build_shared_libraries "shared" else "static";

    log("Compiling zlib for % % %...", os_target, cpu_target, shared_or_static);

    platform_name    := get_platform_name(os_target);
    install_dir      := tprint("%_install", platform_name);
    build_dir        := tprint("%_build", platform_name);
    final_binary_dir := platform_name;

    if os_target == .MACOS && !macos_universal_binaries {
        arch_lower_case := to_lower_copy(tprint("%", cpu_target),, temp);

        install_dir = tprint("%_%_%_install", platform_name, arch_lower_case, shared_or_static);
        build_dir   = tprint("%_%_%_build",   platform_name, arch_lower_case, shared_or_static);
    } else {
        install_dir = tprint("%_%_install", platform_name, shared_or_static);
        build_dir   = tprint("%_%_build",   platform_name, shared_or_static);
    }

    if clean {
        if is_directory(build_dir) {
            log("Deleting previous build directory found at '%'.", build_dir);
            success := delete_directory(build_dir);
            if !success {
                log_error("Could not delete old build directory.");
                return false;
            }
        }

        if is_directory(install_dir) {
            log("Deleting previous install directory found at '%'.", install_dir);
            success := delete_directory(install_dir);
            if !success {
                log_error("Could not delete old install directory.");
                return false;
            }
        }
    }

    success  := make_directory_if_it_does_not_exist(install_dir,      recursive = true);
    success &&= make_directory_if_it_does_not_exist(build_dir,        recursive = true);
    success &&= make_directory_if_it_does_not_exist(final_binary_dir, recursive = true);
    assert(success);

    absolute_install_dir := get_absolute_path(install_dir);
    absolute_build_dir   := get_absolute_path(build_dir);

    assert(absolute_install_dir != "");
    assert(absolute_build_dir   != "");
    assert(file_exists(absolute_install_dir));
    assert(file_exists(absolute_build_dir));

    log("Configuring zlib... \"%\" -> \"%\"", absolute_build_dir, absolute_install_dir);

    absolute_source_path := get_absolute_path(SOURCE_PATH);

    config_command: [..] string;
    array_add(
        *config_command,
        "cmake",
        "-G", "Ninja",
        absolute_source_path,
        tprint("-DCMAKE_INSTALL_PREFIX=%", absolute_install_dir),
        tprint("-DCMAKE_PREFIX_PATH=%",    absolute_install_dir),
    );

    if os_target == .MACOS {
        #if OS == .MACOS {
            POSIX :: #import "POSIX";
            POSIX.setenv("MACOSX_DEPLOYMENT_TARGET", "11.0", 1);

            if macos_universal_binaries {
                array_add(
                    *config_command,
                    "-DCMAKE_OSX_ARCHITECTURES=x86_64;arm64",
                );
            }
        }
    }

    if build_shared_libraries {
        array_add(
            *config_command,
            "-DBUILD_SHARED_LIBS=ON"
        );
    } else {
        array_add(
            *config_command,
            "-DBUILD_SHARED_LIBS=OFF"
        );
    }

    build_type := ifx debug "Debug" else "Release";
    array_add(
        *config_command,
        tprint("-DCMAKE_BUILD_TYPE=%", build_type),
    );

    result := run_command(..config_command, working_directory = absolute_build_dir);
    if !(result.type == .EXITED && result.exit_code == 0) {
        log_error("Failed to configure zlib.");
        return false;
    }

    log("Configuration done!");

    log("Building zlib...");

    build_command: [..] string;
    array_add(
        *build_command,
        "cmake",
        "--build", absolute_build_dir,
        "--target", "install",
    );

    result = run_command(..build_command);
    if !(result.type == .EXITED && result.exit_code == 0) {
        log_error("Failed to build zlib.");
        return false;
    }

    log("Done building zlib!");

    copy_binaries(os_target, absolute_install_dir, final_binary_dir);

    return true;
}

copy_binaries :: (os_target: Operating_System_Tag, install_dir: string, final_binary_dir: string) {
    log("Copying compiled binaries to '%'...", final_binary_dir);

    lib_dir := tprint("%/lib", install_dir);
    bin_dir := tprint("%/bin", install_dir);

    if os_target == .WINDOWS {
        copy_directory(bin_dir, final_binary_dir);
    }

    copy_directory(lib_dir, final_binary_dir);
}

check_dependencies :: (os_target: Operating_System_Tag) -> bool {
    result := run_command("cmake", "--version", capture_and_return_output = true);
    if !(result.type == .EXITED && result.exit_code == 0) {
        log_error("cmake not found in your path, this is required to compile.");
        return false;
    }

    if os_target == .WINDOWS {
        result := run_command("ninja", "--version", capture_and_return_output = true);
        if !(result.type == .EXITED && result.exit_code == 0) {
            log_error("ninja not found in your path, this is required to compile.");
            return false;
        }
    }

    return true;
}

// #if AT_COMPILE_TIME  {
//     #run {
//         set_build_options_dc(.{ do_output = false });

//         root_options := get_build_options();
//         args := root_options.compile_time_command_line;

//         if !generate_zlib(args) {
//             compiler_set_workspace_status(.FAILED);
//         }
//     }
// } else {
//     main :: () {
//         set_working_directory(path_strip_filename(get_path_of_running_executable()));

//         args := get_command_line_arguments();

//         if !generate(args) {
//             exit(1);
//         }
//     }
// }

#import "Basic";
#import "Bindings_Generator";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";