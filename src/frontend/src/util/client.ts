import { IndexClient } from "candb-client-typescript/dist/IndexClient";
import { ActorClient } from "candb-client-typescript/dist/ActorClient";

import { idlFactory as CanDBIndexIDL } from "../../../declarations/CanDBIndex/index";
import { idlFactory as CanDBPartitionIDL } from "../../../declarations/CanDBPartition/index";
import { idlFactory as NacDBPartitionIDL } from "../../../declarations/NacDBPartition/index";
import { idlFactory as MainIDL } from "../../../declarations/main/index";
import { idlFactory as OrderIDL } from "../../../declarations/order/index";
import { CanDBPartition } from "../../../declarations/CanDBPartition/CanDBPartition.did";
import { CanDBIndex } from "../../../declarations/CanDBIndex/CanDBIndex.did";
import { Actor, HttpAgent } from "@dfinity/agent";
import { Principal } from "@dfinity/principal";

export function getIsLocal() {
  return process.env.IS_LOCAL !== '' && process.env.IS_LOCAL !== '0';
}

const isLocal = getIsLocal();

export function intializeCanDBIndexClient(): IndexClient<CanDBIndex> {
  const host = isLocal ? "http://127.0.0.1:8000" : "https://ic0.app";
  const canisterId = isLocal ? process.env.INDEX_CANISTER_ID : "<prod_canister_id>"; // TODO
  return new IndexClient<CanDBIndex>({
    IDL: CanDBIndexIDL,
    canisterId, 
    agentOptions: {
      host,
    },
  });
};

// TODO: Also partition client for a single canister.
export function initializeCanDBPartitionClient(indexClient: IndexClient<CanDBIndex>)
    : ActorClient<CanDBIndex, CanDBPartition>
{
  const host = isLocal ? "http://127.0.0.1:8000" : "https://ic0.app";
  return new ActorClient<CanDBIndex, CanDBPartition>({
    actorOptions: {
      IDL: CanDBPartitionIDL,
      agentOptions: {
        host,
      }
    },
    indexClient, 
  });
};

export function initializeDirectCanDBPartitionClient(canisterId: Principal)
{
  const host = isLocal ? "http://127.0.0.1:8000" : "https://ic0.app";
  const agent = new HttpAgent({ host });
  return Actor.createActor(CanDBPartitionIDL, { agent, canisterId });
};

export function initializeDirectNacDBPartitionClient(canisterId: Principal)
{
  const host = isLocal ? "http://127.0.0.1:8000" : "https://ic0.app";
  const agent = new HttpAgent({ host });
  return Actor.createActor(NacDBPartitionIDL, { agent, canisterId });
};

export function initializeMainClient()
{
  const host = isLocal ? "http://127.0.0.1:8000" : "https://ic0.app";
  const agent = new HttpAgent({ host });
  const canisterId = isLocal ? process.env.MAIN_CANISTER_ID : "<prod_canister_id>"; // TODO
  return Actor.createActor(MainIDL, { agent, canisterId });
};

export function initializeOrderClient()
{
  const host = isLocal ? "http://127.0.0.1:8000" : "https://ic0.app";
  const agent = new HttpAgent({ host });
  const canisterId = isLocal ? process.env.ORDER_CANISTER_ID : "<prod_canister_id>"; // TODO
  return Actor.createActor(OrderIDL, { agent, canisterId });
};