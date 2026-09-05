let searchInput = document.querySelector(
  ".search-field input[type='text'], .search-bar input[type='search'], .search-bar-nav input[type='search']",
);

document.addEventListener("keydown", function (e) {
  if (e.key == "/") {
    searchInput.focus();
    searchInput.select();
    e.preventDefault();
  }
});
