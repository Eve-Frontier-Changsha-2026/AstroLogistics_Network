import type { Page } from '@playwright/test';

// NOTE: HTTPS default port 443 may or may not appear in Request.url().
// Use a pattern that matches both. Adjust after verifying with page.on('request').
const GRPC_PATTERN = '**/fullnode.testnet.sui.io**/sui.rpc.v2.**';

/** Block ALL gRPC calls — simulates network down */
export async function blockAllGrpc(page: Page) {
  await page.route(GRPC_PATTERN, (route) => route.abort('timedout'));
}

/** Block specific gRPC service method */
export async function blockGrpcMethod(page: Page, method: string) {
  await page.route(`**/sui.rpc.v2.${method}`, (route) => route.abort('failed'));
}

/** Return HTTP 503 for all gRPC calls */
export async function grpcServiceUnavailable(page: Page) {
  await page.route(GRPC_PATTERN, (route) =>
    route.fulfill({ status: 503, body: '' }),
  );
}

/** Block only transaction execution — queries still work */
export async function blockTransactionExecution(page: Page) {
  await page.route('**/sui.rpc.v2.TransactionExecutionService/**', (route) =>
    route.abort('failed'),
  );
}

/** Block only object queries — transactions still work */
export async function blockObjectQueries(page: Page) {
  await page.route('**/sui.rpc.v2.StateService/GetObject', (route) =>
    route.abort('failed'),
  );
}

/** Clear all route interceptions */
export async function clearInterceptions(page: Page) {
  await page.unrouteAll({ behavior: 'ignoreErrors' });
}
