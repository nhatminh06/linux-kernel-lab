#include <linux/module.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/mutex.h>
#include <linux/device.h>

#define DEVICE_NAME "mychardev"
#define MSG_SIZE 256

static int major;
static struct class *cls;
static char msg[MSG_SIZE] = {0};
static size_t msg_len;
/* Protects msg/msg_len: read()/write() from different processes race on
 * the single shared buffer without this. */
static DEFINE_MUTEX(dev_lock);

static ssize_t dev_read(struct file *f, char __user *buf, size_t len, loff_t *off) {
    ssize_t ret;

    if (mutex_lock_interruptible(&dev_lock))
        return -ERESTARTSYS;
    ret = simple_read_from_buffer(buf, len, off, msg, msg_len);
    mutex_unlock(&dev_lock);
    return ret;
}

static ssize_t dev_write(struct file *f, const char __user *buf, size_t len, loff_t *off) {
    if (len > MSG_SIZE - 1)
        len = MSG_SIZE - 1;

    if (mutex_lock_interruptible(&dev_lock))
        return -ERESTARTSYS;
    if (copy_from_user(msg, buf, len)) {
        mutex_unlock(&dev_lock);
        return -EFAULT;
    }
    msg[len] = '\0';
    msg_len = len;
    mutex_unlock(&dev_lock);

    /* Report full length written, even though it may have been truncated
     * to fit msg[], so short writes are never falsely reported. */
    return len;
}

static const struct file_operations fops = {
    .owner = THIS_MODULE,
    .read = dev_read,
    .write = dev_write,
};

static int __init chardev_init(void) {
    major = register_chrdev(0, DEVICE_NAME, &fops);
    if (major < 0) {
        printk(KERN_ERR "mychardev: register_chrdev failed: %d\n", major);
        return major;
    }

    cls = class_create(DEVICE_NAME);
    if (IS_ERR(cls)) {
        unregister_chrdev(major, DEVICE_NAME);
        printk(KERN_ERR "mychardev: class_create failed: %ld\n", PTR_ERR(cls));
        return PTR_ERR(cls);
    }

    if (IS_ERR(device_create(cls, NULL, MKDEV(major, 0), NULL, DEVICE_NAME))) {
        class_destroy(cls);
        unregister_chrdev(major, DEVICE_NAME);
        printk(KERN_ERR "mychardev: device_create failed\n");
        return -ENODEV;
    }

    printk(KERN_INFO "mychardev: loaded, major=%d\n", major);
    return 0;
}

static void __exit chardev_exit(void) {
    device_destroy(cls, MKDEV(major, 0));
    class_destroy(cls);
    unregister_chrdev(major, DEVICE_NAME);
    printk(KERN_INFO "mychardev: unloaded\n");
}

module_init(chardev_init);
module_exit(chardev_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Minimal character device driver for read/write testing");
