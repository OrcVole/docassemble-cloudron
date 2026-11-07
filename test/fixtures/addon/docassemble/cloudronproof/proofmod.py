def marker():
    """Report where this module was imported from: it must be /app/data/packages, not the image."""
    return 'ADDON-IMPORTED-FROM=' + __file__
