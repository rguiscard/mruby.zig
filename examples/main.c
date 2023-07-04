#include <stdio.h>
#include <stdlib.h>

#include <mruby.h>
#include <mruby/compile.h>
#include <mruby/string.h>

int main(int argc, char **argv) {
  printf("[c_example] BEGIN MRUBY\n");

  mrb_state *mrb = mrb_open();

  if (!mrb) {
    fprintf(stderr, "mrb_open\n");
    perror("mrb_open");
    exit(-1);
  }

  mrb_show_copyright(mrb);
  mrb_show_version(mrb);

  mrb_value str = mrb_str_new_lit(mrb, "mrb_p");
  mrb_funcall(mrb, str, "upcase!", 0, NULL);
  mrb_p(mrb, str);

  str                = mrb_load_string(mrb, "(2*21).to_s");
  const char *result = mrb_string_cstr(mrb, str);
  printf("[c_example] result: %s\n", result);

  mrb_load_string(mrb, "puts 'hola, mundo!'");

  mrb_close(mrb);

  printf("[c_example] END MRUBY\n");

  return 0;
}
