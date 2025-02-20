phantom_run <- function(args, wait = TRUE, quiet = FALSE) {
  phantom_bin <- find_phantom(quiet = quiet)

  # Handle missing phantomjs
  if (is.null(phantom_bin)) return(NULL)

  # Make sure args is a char vector
  args <- as.character(args)

  p <- callr::process$new(
    phantom_bin,
    args = args,
    stdout = "|", stderr = "|",
    supervise = TRUE
  )

  if (isTRUE(wait)) {
    on.exit({
      p$kill()
    })
    cat_n <- function(txt) {
      if (length(txt) > 0) {
        cat(txt, sep = "\n")
      }
    }
    while(p$is_alive()) {
      p$wait(200) # wait until min(c(time_ms, process ends))
      cat_n(p$read_error_lines())
      cat_n(p$read_output_lines())
    }
  }
  p$get_exit_status()
}


# Find PhantomJS from PATH, APPDATA, system.file('webshot'), ~/bin, etc
find_phantom <- function(quiet = FALSE) {
  path <- Sys.which( "phantomjs" )
  if (path != "") return(path)

  for (d in phantom_paths()) {
    exec <- if (is_windows()) "phantomjs.exe" else "phantomjs"
    path <- file.path(d, exec)
    if (utils::file_test("-x", path)) break else path <- ""
  }

  if (path == "") {
    # It would make the most sense to throw an error here. However, that would
    # cause problems with CRAN. The CRAN checking systems may not have phantomjs
    # and may not be capable of installing phantomjs (like on Solaris), and any
    # packages which use webshot in their R CMD check (in examples or vignettes)
    # will get an ERROR. We'll issue a message and return NULL; other

    if(!quiet) {
      message(
        "PhantomJS not found. You can install it with webshot::install_phantomjs(). ",
        "If it is installed, please make sure the phantomjs executable ",
        "can be found via the PATH variable."
      )
    }
    return(NULL)
  }
  path.expand(path)
}

phantomjs_cmd_result <- function(args, wait = TRUE, quiet = FALSE) {
  # Retrieve and store output from STDOUT
  utils::capture.output(invisible(phantom_run(args = args, wait = wait, quiet = quiet)),
                        type = "output")
}

phantomjs_version <- function() {
  phantomjs_cmd_result("--version", quiet = TRUE)
}

#' Determine if PhantomJS is Installed
#'
#' Verifies that a version of PhantomJS is installed and available for use
#' on the user's computer.
#'
#' @return \code{TRUE} if the PhantomJS is installed. Otherwise, \code{FALSE}
#' if PhantomJS is not installed.
#'
#' @export
is_phantomjs_installed <- function() {
  !is.null(find_phantom(quiet = TRUE))
}

is_phantomjs_version_latest <- function(requested_version) {
  # Ensure phantomjs is installed if not, request an update
  if (!is_phantomjs_installed()) {
    return(FALSE)
  }

  # Obtain the installed version
  installed_phantomjs_version <- phantomjs_version()

  # For versions 2.5.0-beta and 2.5.0-beta2, phantomjs reports its version to be
  # "2.5.0-development".
  #
  # However, for the requested version, we have the names "2.5.0-beta" and
  # "2.5.0-beta2".
  #
  # For simplicity, we'll just remove the "-development" or "-beta" or "-beta2"
  # so they all map to "2.5.0".
  installed_phantomjs_version <- sub("-development", "", installed_phantomjs_version)
  requested_version           <- sub("-beta.*",      "", requested_version)

  # Check if the installed version is latest compared to requested version.
  as.package_version(installed_phantomjs_version) >= requested_version
}


#' Install PhantomJS
#'
#' Download the zip package, unzip it, and copy the executable to a system
#' directory in which \pkg{webshot} can look for the PhantomJS executable.
#'
#' @details This function was designed primarily to help Windows users since it
#'   is cumbersome to modify the \code{PATH} variable. Mac OS X users may
#'   install PhantomJS via Homebrew. If you download the package from the
#'   PhantomJS website instead, please make sure the executable can be found via
#'   the \code{PATH} variable.
#'
#'   On Windows, the directory specified by the environment variable
#'   \code{APPDATA} is used to store \file{phantomjs.exe}. On OS X, the
#'   directory \file{~/Library/Application Support} is used. On other platforms
#'   (such as Linux), the directory \file{~/bin} is used. If these directories
#'   are not writable, the directory \file{PhantomJS} under the installation
#'   directory of the \pkg{webshot} package will be tried. If this directory
#'   still fails, you will have to install PhantomJS by yourself.
#'
#'   If PhantomJS is not already installed on the computer, this function will
#'   attempt to install it. However, if the version of PhantomJS installed is
#'   greater than or equal to the requested version, this function will not
#'   perform the installation procedure again unless the \code{force} parameter
#'   is set to \code{TRUE}. As a result, this function may also be used to
#'   reinstall or downgrade the version of PhantomJS found.
#'
#' @param version The version number of PhantomJS.
#' @param baseURL The base URL for the location of PhantomJS binaries for
#'   download. If the default download site is unavailable, you may specify an
#'   alternative mirror, such as
#'   \code{"https://bitbucket.org/ariya/phantomjs/downloads/"}.
#' @param force Install PhantomJS even if the version installed is the latest or
#'   if the requested version is older. This is useful to reinstall or downgrade
#'   the version of PhantomJS.
#' @return \code{NULL} (the executable is written to a system directory).
#' @export
install_phantomjs <- function(version = '2.1.1',
    baseURL = 'https://github.com/wch/webshot/releases/download/v0.3.1/',
    force = FALSE) {

  if (!force && is_phantomjs_version_latest(version)) {
      message('It seems that the version of `phantomjs` installed is ',
              'greater than or equal to the requested version.',
              'To install the requested version or downgrade to another version, ',
              'use `force = TRUE`.')
      return(invisible())
  }

  if (!grepl("/$", baseURL))
    baseURL <- paste0(baseURL, "/")

  owd <- setwd(tempdir())
  on.exit(setwd(owd), add = TRUE)
  if (is_windows()) {
    zipfile <- sprintf('phantomjs-%s-windows.zip', version)
    download(paste0(baseURL, zipfile), zipfile, mode = 'wb')
    utils::unzip(zipfile)
    zipdir <- sub('.zip$', '', zipfile)
    exec <- file.path(zipdir, 'bin', 'phantomjs.exe')
  } else if (is_osx()) {
    zipfile <- sprintf('phantomjs-%s-macosx.zip', version)
    download(paste0(baseURL, zipfile), zipfile, mode = 'wb')
    utils::unzip(zipfile)
    zipdir <- sub('.zip$', '', zipfile)
    exec <- file.path(zipdir, 'bin', 'phantomjs')
    Sys.chmod(exec, '0755')  # chmod +x
  } else if (is_linux()) {
    zipfile <- sprintf(
      'phantomjs-%s-linux-%s.tar.bz2', version,
      if (grepl('64', Sys.info()[['machine']])) 'x86_64' else 'i686'
    )
    download(paste0(baseURL, zipfile), zipfile, mode = 'wb')
    utils::untar(zipfile)
    zipdir <- sub('.tar.bz2$', '', zipfile)
    exec <- file.path(zipdir, 'bin', 'phantomjs')
    Sys.chmod(exec, '0755')  # chmod +x
  } else {
    # Unsupported platform, like Solaris
    message("Sorry, this platform is not supported.")
    return(invisible())
  }
  success <- FALSE
  dirs <- phantom_paths()
  for (destdir in dirs) {
    dir.create(destdir, showWarnings = FALSE)
    success <- file.copy(exec, destdir, overwrite = TRUE)
    if (success) break
  }
  unlink(c(zipdir, zipfile), recursive = TRUE)
  if (!success) stop(
    'Unable to install PhantomJS to any of these dirs: ',
    paste(dirs, collapse = ', ')
  )
  message('phantomjs has been installed to ', normalizePath(destdir))
  invisible()
}

# Possible locations of the PhantomJS executable
phantom_paths <- function() {
  if (is_windows()) {
    path <- Sys.getenv('APPDATA', '')
    path <- if (dir_exists(path)) file.path(path, 'PhantomJS')
  } else if (is_osx()) {
    path <- '~/Library/Application Support'
    path <- if (dir_exists(path)) file.path(path, 'PhantomJS')
  } else {
    path <- '~/bin'
  }
  path <- c(path, file.path(system.file(package = 'webshot'), 'PhantomJS'))
  path
}

dir_exists <- function(path) utils::file_test('-d', path)

# Given a vector or list, drop all the NULL items in it
dropNulls <- function(x) {
  x[!vapply(x, is.null, FUN.VALUE=logical(1))]
}

is_windows <- function() .Platform$OS.type == "windows"
is_osx     <- function() Sys.info()[['sysname']] == 'Darwin'
is_linux   <- function() Sys.info()[['sysname']] == 'Linux'
is_solaris <- function() Sys.info()[['sysname']] == 'SunOS'

# Find an available TCP port (to launch Shiny apps)
available_port <- function(port = NULL, min = 3000, max = 9000) {
  if (!is.null(port)) return(port)

  # Unsafe port list from shiny::runApp()
  valid_ports <- setdiff(min:max, c(3659, 4045, 6000, 6665:6669, 6697))

  # Try up to 20 ports
  for (port in sample(valid_ports, 20)) {
    handle <- NULL

    # Check if port is open
    tryCatch(
      handle <- httpuv::startServer("127.0.0.1", port, list()),
      error = function(e) { }
    )
    if (!is.null(handle)) {
      httpuv::stopServer(handle)
      return(port)
    }
  }

  stop("Cannot find an available port")
}

# Wrapper for utils::download.file which works around a problem with R 3.3.0 and
# 3.3.1. In these versions, download.file(method="libcurl") issues a HEAD
# request to check if a file is available, before sending the GET request. This
# causes problems when downloading attached files from GitHub binary releases
# (like the PhantomJS binaries), because the url for the GET request returns a
# 403 for HEAD requests. See
# https://stat.ethz.ch/pipermail/r-devel/2016-June/072852.html
download <- function(url, destfile, mode = "w") {
  if (getRversion() >= "3.3.0") {
    download_no_libcurl(url, destfile, mode = mode)

  } else if (is_windows() && getRversion() < "3.2") {
    # Older versions of R on Windows need setInternet2 to download https.
    download_old_win(url, destfile, mode = mode)

  } else {
    utils::download.file(url, destfile, mode = mode)
  }
}


# Adapted from downloader::download, but avoids using libcurl.
download_no_libcurl <- function(url, ...) {
  # Windows
  if (is_windows()) {
    method <- "wininet"
    utils::download.file(url, method = method, ...)

  } else {
    # If non-Windows, check for libcurl/curl/wget/lynx, then call download.file with
    # appropriate method.

    if (nzchar(Sys.which("wget")[1])) {
      method <- "wget"
    } else if (nzchar(Sys.which("curl")[1])) {
      method <- "curl"

      # curl needs to add a -L option to follow redirects.
      # Save the original options and restore when we exit.
      orig_extra_options <- getOption("download.file.extra")
      on.exit(options(download.file.extra = orig_extra_options))

      options(download.file.extra = paste("-L", orig_extra_options))

    } else if (nzchar(Sys.which("lynx")[1])) {
      method <- "lynx"
    } else {
      stop("no download method found")
    }

    utils::download.file(url, method = method, ...)
  }
}


# Adapted from downloader::download, for R<3.2 on Windows
download_old_win <- function(url, ...) {
  # If we directly use setInternet2, R CMD CHECK gives a Note on Mac/Linux
  seti2 <- `::`(utils, 'setInternet2')

  # Check whether we are already using internet2 for internal
  internet2_start <- seti2(NA)

  # If not then temporarily set it
  if (!internet2_start) {
    # Store initial settings, and restore on exit
    on.exit(suppressWarnings(seti2(internet2_start)))

    # Needed for https. Will get warning if setInternet2(FALSE) already run
    # and internet routines are used. But the warnings don't seem to matter.
    suppressWarnings(seti2(TRUE))
  }

  method <- "internal"

  # download.file will complain about file size with something like:
  #       Warning message:
  #         In download.file(url, ...) : downloaded length 19457 != reported length 200
  # because apparently it compares the length with the status code returned (?)
  # so we supress that
  utils::download.file(url, method = method, ...)
}


# Fix local filenames like "c:/path/file.html" to "file:///c:/path/file.html"
# because that's the format used by casperjs and the webshot.js script.
fix_windows_url <- function(url) {
  if (!is_windows()) return(url)

  fix_one <- function(x) {
    # If it's a "c:/path/file.html" path, or contains any backslashs, like
    # "c:\path", "\\path\\file.html", or "/path\\file.html", we need to fix it
    # up. However, we need to leave paths that are already URLs alone.
    if (grepl("^[a-zA-Z]:/", x) ||
        (!grepl(":", x, fixed = TRUE) && grepl("\\", x, fixed = TRUE)))
    {
      paste0("file:///", normalizePath(x, winslash = "/"))
    } else {
      x
    }
  }

  vapply(url, fix_one, character(1), USE.NAMES = FALSE)
}


# Borrowed from animation package, with some adaptations.
find_magic = function() {
  # try to look for ImageMagick in the Windows Registry Hive, the Program Files
  # directory and the LyX installation
  if (!inherits(try({
    magick.path = utils::readRegistry('SOFTWARE\\ImageMagick\\Current')$BinPath
  }, silent = TRUE), 'try-error')) {
    if (nzchar(magick.path)) {
      convert = normalizePath(file.path(magick.path, 'convert.exe'), "/", mustWork = FALSE)
    }
  } else if (
    nzchar(prog <- Sys.getenv('ProgramFiles')) &&
      length(magick.dir <- list.files(prog, '^ImageMagick.*')) &&
      length(magick.path <- list.files(file.path(prog, magick.dir), pattern = '^convert\\.exe$',
                                       full.names = TRUE, recursive = TRUE))
  ) {
    convert = normalizePath(magick.path[1], "/", mustWork = FALSE)
  } else if (!inherits(try({
    magick.path = utils::readRegistry('LyX.Document\\Shell\\open\\command', 'HCR')
  }, silent = TRUE), 'try-error')) {
    convert = file.path(dirname(gsub('(^\"|\" \"%1\"$)', '', magick.path[[1]])), c('..', '../etc'),
                        'imagemagick', 'convert.exe')
    convert = convert[file.exists(convert)]
    if (length(convert)) {
      convert = normalizePath(convert, "/", mustWork = FALSE)
    } else {
      warning('No way to find ImageMagick!')
      return("")
    }
  } else {
    warning('ImageMagick not installed yet!')
    return("")
  }

  if (!file.exists(convert)) {
    # Found an ImageMagick installation, but not the convert.exe binary.
    warning("ImageMagick's convert.exe not found at ", convert)
    return("")
  }
  return(convert)
}
