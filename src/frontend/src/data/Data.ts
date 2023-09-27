import { Principal } from "@dfinity/principal";
import { Item, Streams } from "../../../declarations/CanDBPartition/CanDBPartition.did"
import { initializeDirectCanDBPartitionClient, initializeDirectNacDBPartitionClient } from "../util/client";

type ItemRef = {
    canister: Principal;
    id: number;
};

function parseItemRef(itemId: string): ItemRef {
    const a = itemId.split('@', 2);
    return {canister: Principal.fromText(a[1]), id: parseInt(a[0])};
}

// TODO
export class BaseItemData {
    itemRef: ItemRef;
    item: Item;
    streams: Streams | null;
    protected constructor(itemId: string) {
        this.itemRef = parseItemRef(itemId);
    }
    static async create(itemId: string, Creator) {
        const obj = new Creator(itemId);
        const client = initializeDirectCanDBPartitionClient(obj.itemRef.canister);
        // TODO: Retrieve both by one call?
        [obj.item, obj.streams] = await Promise.all([
            await client.getItem(obj.itemRef.id),
            await client.getStreams(obj.itemRef.id)
        ])
    }
    locale() {
        return this.item.item.locale;
    }
    title() {
        return this.item.item.title;
    }
    description() {
        return this.item.item.description;
    }
    // FIXME below
    // FIXME: For non-folders, no distinction between `subCategories` and `items` (or better no subcategories?)
    async subCategories() {
        // TODO: duplicate code
        if (this.streams === null) {
            return [];
        }
        const [outerCanister, outerKey] = this.streams.categoriesTimeOrderSubDB
        const client = initializeDirectNacDBPartitionClient(Principal.from(outerCanister)); // FIXME: Does `from` work?
        const items = await client.scanLimitOuter({outerKey, lowerBound: "", upperBound: "x", dir: 'fwd', limit: 10}) as // TODO: limit
            Array<[string, number]>; // FIXME: correct type?
        const items2 = items.map(([principalStr, id]) => { return {canister: Principal.from(principalStr), id: id} });
        const items3 = items2.map(id => async () => [id, await client.getItem(id)]);
        const items4 = (await Promise.all(items3)) as unknown as [number, Item][]; // TODO: correct?
        return items4.map(([id, item]) => {
            return {
                id,
                locale: item.item.locale,
                title: item.item.title,
                description: item.item.description,
                type: 'public', // FIXME
            }
        });
    }
    async superCategories() { // TODO
        return [
            {id: 1, locale: "en", title: "All the World", type: 'public'},
            {id: 4, locale: "en", title: "John's notes", type: 'private', description: "John writes about everything, including the content of The Homepage."},
        ];
    }
    async items() {
        // TODO: duplicate code
        if (this.streams === null) {
            return [];
        }
        const [outerCanister, outerKey] = this.streams.categoriesTimeOrderSubDB
        const client = initializeDirectNacDBPartitionClient(Principal.from(outerCanister)); // FIXME: Does `from` work?
        const items = await client.scanLimitOuter({outerKey, lowerBound: "", upperBound: "x", dir: 'fwd', limit: 10}) as // TODO: limit
            Array<[string, number]>; // FIXME: correct type?
        const items2 = items.map(([principalStr, id]) => { return {canister: Principal.from(principalStr), id: id} });
        const items3 = items2.map(id => async () => [id, await client.getItem(id)]);
        const items4 = (await Promise.all(items3)) as unknown as [number, Item][]; // TODO: correct?
        return items4.map(([id, item]) => {
            return {
                id,
                locale: item.item.locale,
                title: item.item.title,
                description: item.item.description,
            }
        })
    }
}

export class FolderData extends BaseItemData{
}