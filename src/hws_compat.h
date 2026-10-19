// SPDX-License-Identifier: GPL-2.0-only
/*
 * Longtimetech HWS V4L2 driver
 * Copyright (C) 2025 Longtimetech
 */

#include <linux/version.h>
#include <media/v4l2-fh.h>

/* vb2 wait_prepare/finish removed in new kernels (>= 6.19/7.0) */

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6,19,0)

#define HWS_VB2_WAIT_OPS

#else

#define HWS_VB2_WAIT_OPS \
    .wait_prepare = vb2_ops_wait_prepare, \
    .wait_finish  = vb2_ops_wait_finish,

#endif


/* v4l2 fh compat */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6,18,0)
#define HWS_V4L2_FH_ADD(fh, file) v4l2_fh_add((fh), (file))
#define HWS_V4L2_FH_DEL(fh, file) v4l2_fh_del((fh), (file))
#else
#define HWS_V4L2_FH_ADD(fh, file) v4l2_fh_add((fh))
#define HWS_V4L2_FH_DEL(fh, file) v4l2_fh_del((fh))
#endif


/*
 * PCI legacy INTx IRQ flag compatibility
 *
 * Some kernels use PCI_IRQ_LEGACY.
 * Some newer kernels use PCI_IRQ_INTX.
 * Some vendor kernels may only define one of them.
 */
#if defined(PCI_IRQ_INTX)
#define HWS_PCI_IRQ_INTX_FLAG PCI_IRQ_INTX
#elif defined(PCI_IRQ_LEGACY)
#define HWS_PCI_IRQ_INTX_FLAG PCI_IRQ_LEGACY
#else
#define HWS_PCI_IRQ_INTX_FLAG 0
#endif

#if LINUX_VERSION_CODE < KERNEL_VERSION(4,16,0)
typedef unsigned int hws_poll_t;
#define HWS_POLLERR POLLERR
#else
typedef __poll_t hws_poll_t;
#define HWS_POLLERR EPOLLERR
#endif