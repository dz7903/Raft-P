test tcSingleClient [main = TestWithSingleClient]:
    union { Server }, { Client }, { ElectionTimer }, { TestWithSingleClient };

test tcMultipleClient [main = TestWithMultipleClient]:
    union { Server }, { Client }, { ElectionTimer }, { TestWithMultipleClient };