window.setTabByName = (tabName) => {
  window.location.hash = `tab-${tabName}`

  return tabName
}

// The conditionals and currIndex stuff ensures that
// the tab index is always set to 0 if the hash is empty
// AND other hash values are ignored
window.getTabFromHash = (currentTabName, defaultTabName, validTabNames) => {
  if (window.location.hash === '' || window.location.hash === '#') {
    return defaultTabName
  }

  if (window.location.hash.startsWith('#tab-')) {
    const tabName = window.location.hash.replace('#tab-', '')

    // A hash naming a tab this page doesn't have (a stale link, or a tab that has
    // since been renamed) would otherwise select nothing and hide every panel
    if (!validTabNames || validTabNames.includes(tabName)) {
      return tabName
    }

    return defaultTabName
  }

  return currentTabName
}
