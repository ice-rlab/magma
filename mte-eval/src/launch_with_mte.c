#define _GNU_SOURCE

#include <errno.h>
#include <linux/prctl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <unistd.h>

#ifndef PR_SET_TAGGED_ADDR_CTRL
#define PR_SET_TAGGED_ADDR_CTRL 55
#endif

#ifndef PR_GET_TAGGED_ADDR_CTRL
#define PR_GET_TAGGED_ADDR_CTRL 56
#endif

#ifndef PR_TAGGED_ADDR_ENABLE
#define PR_TAGGED_ADDR_ENABLE (1UL << 0)
#endif

#ifndef PR_MTE_TCF_SHIFT
#define PR_MTE_TCF_SHIFT 1
#endif

#ifndef PR_MTE_TCF_SYNC
#define PR_MTE_TCF_SYNC (1UL << PR_MTE_TCF_SHIFT)
#endif

#ifndef PR_MTE_TAG_SHIFT
#define PR_MTE_TAG_SHIFT 3
#endif

static unsigned long build_mte_ctrl(void) {
  /* Allow non-zero allocation tags 1..15 and request synchronous faults. */
  return PR_TAGGED_ADDR_ENABLE | PR_MTE_TCF_SYNC |
         (0xfffeUL << PR_MTE_TAG_SHIFT);
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: %s <program> [args...]\n", argv[0]);
    return 2;
  }

  unsigned long ctrl = build_mte_ctrl();
  if (prctl(PR_SET_TAGGED_ADDR_CTRL, ctrl, 0, 0, 0) != 0) {
    fprintf(stderr, "PR_SET_TAGGED_ADDR_CTRL failed: errno=%d (%s)\n", errno,
            strerror(errno));
    return 1;
  }

  long current = prctl(PR_GET_TAGGED_ADDR_CTRL, 0, 0, 0, 0);
  if (current < 0) {
    fprintf(stderr, "PR_GET_TAGGED_ADDR_CTRL failed: errno=%d (%s)\n", errno,
            strerror(errno));
    return 1;
  }

  fprintf(stderr, "launch_with_mte: tagged_addr_ctrl=0x%lx\n",
          (unsigned long)current);
  execvp(argv[1], &argv[1]);

  fprintf(stderr, "execvp failed: errno=%d (%s)\n", errno, strerror(errno));
  return 1;
}
