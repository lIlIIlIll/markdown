#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef GFM
#include "cmark-gfm.h"
#include "cmark-gfm-extension_api.h"
#include "cmark-gfm-core-extensions.h"
#include "registry.h"
#else
#include "cmark.h"
#endif

static char *read_all(size_t *length) {
  size_t capacity = 65536;
  char *buffer = malloc(capacity);
  if (!buffer) return NULL;
  *length = 0;
  for (;;) {
    if (*length == capacity) {
      capacity *= 2;
      char *next = realloc(buffer, capacity);
      if (!next) { free(buffer); return NULL; }
      buffer = next;
    }
    size_t count = fread(buffer + *length, 1, capacity - *length, stdin);
    *length += count;
    if (count == 0) break;
  }
  return buffer;
}

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  long iterations = strtol(argv[1], NULL, 10);
  if (iterations <= 0) return 2;
  size_t length = 0;
  char *input = read_all(&length);
  if (!input) return 1;
  size_t observed = 0;
#ifdef GFM
  cmark_gfm_core_extensions_ensure_registered();
  cmark_mem *mem = cmark_get_default_mem_allocator();
  const char *names[] = {"table", "strikethrough", "autolink", "tagfilter", "tasklist"};
  cmark_llist *extensions = NULL;
  for (size_t index = 0; index < sizeof(names) / sizeof(names[0]); index++) {
    cmark_syntax_extension *extension = cmark_find_syntax_extension(names[index]);
    if (!extension) return 1;
    extensions = cmark_llist_append(mem, extensions, extension);
  }
  for (long iteration = 0; iteration < iterations; iteration++) {
    cmark_parser *parser = cmark_parser_new(CMARK_OPT_UNSAFE);
    for (cmark_llist *item = extensions; item; item = item->next)
      cmark_parser_attach_syntax_extension(parser, item->data);
    cmark_parser_feed(parser, input, length);
    cmark_node *document = cmark_parser_finish(parser);
    char *html = cmark_render_html(document, CMARK_OPT_UNSAFE, extensions);
    observed += strlen(html);
    free(html);
    cmark_node_free(document);
    cmark_parser_free(parser);
  }
  cmark_llist_free(mem, extensions);
  cmark_release_plugins();
#else
  for (long iteration = 0; iteration < iterations; iteration++) {
    cmark_node *document = cmark_parse_document(input, length, CMARK_OPT_DEFAULT);
    if (!document) return 1;
    observed += (size_t)cmark_node_get_start_line(document);
    cmark_node_free(document);
  }
#endif
  free(input);
  printf("%zu\n", observed);
  return 0;
}
