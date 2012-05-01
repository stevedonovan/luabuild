#include "queue.h"
#include <stdlib.h>

static int _queue_resize(queue* q, int new_cap)
{
    int* new_queue;
    int i;

    if (new_cap <= q->cap) {
        return 0;
    }
    if ((new_queue = (int*)malloc(new_cap * sizeof(int))) == NULL) {
        return 0;
    }
    if (q->front <= q->back) {
        q->front = q->front + q->cap;
    }
    for (i = q->back; i < q->front; ++i) {
        new_queue[i - q->back] = q->queue[i % q->cap];
    }
    free(q->queue);
    q->queue = new_queue;
    q->cap = new_cap;
    q->front = q->size;
    q->back = 0;

    return 1;
}

int queue_init(queue* q, int cap)
{
    if (cap < 1) {
        return 0;
    }
    if ((q->queue = (int*)malloc(cap * sizeof(int))) == NULL) {
        return 0;
    }
    q->size = 0;
    q->cap = cap;
    q->front = 0;
    q->back = 0;

    return 1;
}

int enqueue(queue* q, int item)
{
    if (q->size == q->cap) {
        if (!_queue_resize(q, 2 * q->cap)) {
            return 0;
        }
    }
    q->queue[q->front++] = item;
    q->front %= q->cap;
    ++q->size;

    return 1;
}

int dequeue(queue* q)
{
    int ret;

    if (q->size == 0) {
        return -1;
    }
    ret = q->queue[q->back++];
    q->back %= q->cap;
    --q->size;

    return ret;
}

void queue_delete(queue* q)
{
    free(q->queue);
    q->queue = NULL;
    q->size = 0;
    q->cap = 0;
}
