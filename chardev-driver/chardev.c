#include <linux/module.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/cdev.h>

#define DEVICE_NAME "mychardev"
static int major;
static char msg[256] = {0};
static struct class *cls;

static ssize_t dev_read(struct file *f, char *buf, size_t len, loff_t *off) {
    return simple_read_from_buffer(buf, len, off, msg, strlen(msg));
}
static ssize_t dev_write(struct file *f, const char *buf, size_t len, loff_t *off) {
    if (len > sizeof(msg) - 1) len = sizeof(msg) - 1;
    if (copy_from_user(msg, buf, len)) return -EFAULT;
    msg[len] = '\0';
    return len;
}
static struct file_operations fops = { .read = dev_read, .write = dev_write };

static int __init chardev_init(void) {
    major = register_chrdev(0, DEVICE_NAME, &fops);
    cls = class_create(DEVICE_NAME);
    device_create(cls, NULL, MKDEV(major, 0), NULL, DEVICE_NAME);
    printk(KERN_INFO "mychardev: loaded, major=%d\n", major);
    return 0;
}
static void __exit chardev_exit(void) {
    device_destroy(cls, MKDEV(major, 0));
    class_destroy(cls);
    unregister_chrdev(major, DEVICE_NAME);
}
module_init(chardev_init);
module_exit(chardev_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Minimal character device driver for read/write testing");
