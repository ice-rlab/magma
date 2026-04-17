#define _GNU_SOURCE

#include <errno.h>
#include <linux/prctl.h>
#include <stdio.h>
#include <string.h>
#include <sys/auxv.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <unistd.h>

#ifndef HWCAP2_MTE
#define HWCAP2_MTE (1UL << 18)
#endif

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

#ifndef PR_MTE_TCF_NONE
#define PR_MTE_TCF_NONE (0UL << PR_MTE_TCF_SHIFT)
#endif

#ifndef PR_MTE_TCF_SYNC
#define PR_MTE_TCF_SYNC (1UL << PR_MTE_TCF_SHIFT)
#endif

#ifndef PR_MTE_TCF_ASYNC
#define PR_MTE_TCF_ASYNC (2UL << PR_MTE_TCF_SHIFT)
#endif

#ifndef PROT_MTE
#define PROT_MTE 0x20
#endif

static const char *tcf_mode(unsigned long ctrl) {
  switch (ctrl & (3UL << PR_MTE_TCF_SHIFT)) {
  case PR_MTE_TCF_NONE:
    return "none";
  case PR_MTE_TCF_SYNC:
    return "sync";
  case PR_MTE_TCF_ASYNC:
    return "async";
  default:
    return "unknown";
  }
}

int main(void) {
  unsigned long hwcap2 = getauxval(AT_HWCAP2);
  long ctrl = prctl(PR_GET_TAGGED_ADDR_CTRL, 0, 0, 0, 0);
  void *ptr = mmap(NULL, 4096, PROT_READ | PROT_WRITE | PROT_MTE,
                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);

  printf("HWCAP2_MTE=%s\n", (hwcap2 & HWCAP2_MTE) ? "yes" : "no");
  if (ctrl < 0) {
    printf("PR_GET_TAGGED_ADDR_CTRL=error errno=%d (%s)\n", errno,
           strerror(errno));
  } else {
    printf("PR_GET_TAGGED_ADDR_CTRL=0x%lx\n", (unsigned long)ctrl);
    printf("tagged_addr_enable=%s\n",
           (ctrl & PR_TAGGED_ADDR_ENABLE) ? "yes" : "no");
    printf("mte_tcf_mode=%s\n", tcf_mode((unsigned long)ctrl));
  }

  if (ptr == MAP_FAILED) {
    printf("mmap(PROT_MTE)=failed errno=%d (%s)\n", errno, strerror(errno));
  } else {
    printf("mmap(PROT_MTE)=ok\n");
    munmap(ptr, 4096);
  }
  return 0;
}
