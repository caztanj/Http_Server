#run {
    set_working_directory(tprint("%/modules/LibreSSL", path_strip_filename(#filepath)));

    #load "modules/LibreSSL/generate.jai";
}

#import "Basic";