#include <linux/module.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/mutex.h>
#include <linux/device.h>

#define DEVICE_NAME "mychardev"
#define MSG_SIZE 256
#define RING_CAPACITY 16

struct message {
    size_t len;
    char data[MSG_SIZE];
};

struct message_ring {
    struct message entries[RING_CAPACITY];
    size_t head;
    size_t tail;
    size_t count;
    size_t read_offset;
};

static int major;
static struct class *cls;
static struct message_ring ring;
/* Protects the queue and the partial-read position. */
static DEFINE_MUTEX(dev_lock);

static ssize_t dev_read(struct file *file, char __user *buf, size_t len,
            loff_t *off)
{
    struct message *message;
    size_t bytes;

    (void)file;
    (void)off;

    if (mutex_lock_interruptible(&dev_lock))
        return -ERESTARTSYS;

    if (!ring.count || !len) {
        mutex_unlock(&dev_lock);
        return 0;
    }

    message = &ring.entries[ring.head];
    bytes = min(len, message->len - ring.read_offset);
    if (copy_to_user(buf, message->data + ring.read_offset, bytes)) {
        mutex_unlock(&dev_lock);
        return -EFAULT;
    }

    ring.read_offset += bytes;
    if (ring.read_offset == message->len) {
        ring.head = (ring.head + 1) % RING_CAPACITY;
        ring.count--;
        ring.read_offset = 0;
    }

    mutex_unlock(&dev_lock);
    return bytes;
}

static ssize_t dev_write(struct file *file, const char __user *buf, size_t len,
             loff_t *off)
{
    struct message *message;

    (void)file;
    (void)off;

    if (!len)
        return 0;
    if (len > MSG_SIZE)
        len = MSG_SIZE;

    if (mutex_lock_interruptible(&dev_lock))
        return -ERESTARTSYS;

    if (ring.count == RING_CAPACITY) {
        mutex_unlock(&dev_lock);
        return -ENOSPC;
    }

    message = &ring.entries[ring.tail];
    if (copy_from_user(message->data, buf, len)) {
        mutex_unlock(&dev_lock);
        return -EFAULT;
    }

    message->len = len;
    ring.tail = (ring.tail + 1) % RING_CAPACITY;
    ring.count++;
    mutex_unlock(&dev_lock);

    return len;
}

static const struct file_operations fops = {
    .owner = THIS_MODULE,
    .read = dev_read,
    .write = dev_write,
};

static int __init chardev_init(void)
{
    struct device *device;
    int ret;

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

    device = device_create(cls, NULL, MKDEV(major, 0), NULL, DEVICE_NAME);
    if (IS_ERR(device)) {
        ret = PTR_ERR(device);
        class_destroy(cls);
        unregister_chrdev(major, DEVICE_NAME);
        printk(KERN_ERR "mychardev: device_create failed: %d\n", ret);
        return ret;
    }

    printk(KERN_INFO "mychardev: loaded, major=%d\n", major);
    return 0;
}

static void __exit chardev_exit(void)
{
    device_destroy(cls, MKDEV(major, 0));
    class_destroy(cls);
    unregister_chrdev(major, DEVICE_NAME);
    printk(KERN_INFO "mychardev: unloaded\n");
}

module_init(chardev_init);
module_exit(chardev_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Message-oriented ring-buffer character device driver");
