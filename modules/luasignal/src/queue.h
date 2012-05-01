#ifndef QUEUE_H
#define QUEUE_H

typedef struct _queue {
    int* queue;
    int size;
    int cap;
    int front;
    int back;
} queue;

int queue_init(queue* q, int cap);
int enqueue(queue* q, int item);
int dequeue(queue* q);
void queue_delete(queue* q);

#endif
